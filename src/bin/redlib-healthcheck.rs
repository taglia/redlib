//! Shell-free, Reddit-independent container liveness check.
use std::io::{Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream};
use std::time::{Duration, Instant};

#[derive(Debug)]
struct Config {
	address: SocketAddr,
	timeout: Duration,
}

impl Config {
	fn parse(host: Option<&str>, port: Option<&str>, app_port: Option<&str>, timeout: Option<&str>) -> Result<Self, String> {
		let host = host.unwrap_or("127.0.0.1");
		// Numeric addresses avoid DNS lookups outside our overall timeout.
		let host: IpAddr = host.parse().map_err(|_| "REDLIB_HEALTHCHECK_HOST must be an IPv4 or IPv6 address".to_string())?;
		let port = port.or(app_port).unwrap_or("8080");
		let port: u16 = port
			.parse()
			.ok()
			.filter(|p| *p != 0)
			.ok_or("REDLIB_HEALTHCHECK_PORT (or PORT) must be between 1 and 65535")?;
		let seconds: u64 = timeout
			.unwrap_or("5")
			.parse()
			.ok()
			.filter(|s| (1..=60).contains(s))
			.ok_or("REDLIB_HEALTHCHECK_TIMEOUT must be an integer between 1 and 60 seconds")?;
		Ok(Self {
			address: SocketAddr::new(host, port),
			timeout: Duration::from_secs(seconds),
		})
	}
}

fn remaining(deadline: Instant) -> Result<Duration, String> {
	deadline
		.checked_duration_since(Instant::now())
		.filter(|d| !d.is_zero())
		.ok_or_else(|| "overall timeout exceeded".into())
}

fn io_error(operation: &str, error: std::io::Error) -> String {
	match error.kind() {
		std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock => format!("{operation} timed out"),
		_ => format!("{operation} failed: {error}"),
	}
}

fn healthy(config: &Config) -> Result<(), String> {
	let deadline = Instant::now() + config.timeout;
	let mut socket = TcpStream::connect_timeout(&config.address, remaining(deadline)?).map_err(|e| io_error("connection", e))?;
	let request = format!("GET /settings HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n\r\n", config.address);
	let mut pending = request.as_bytes();
	while !pending.is_empty() {
		socket
			.set_write_timeout(Some(remaining(deadline)?))
			.map_err(|e| format!("setting write timeout failed: {e}"))?;
		let written = socket.write(pending).map_err(|e| io_error("sending request", e))?;
		if written == 0 {
			return Err("connection closed while sending request".into());
		}
		pending = &pending[written..];
	}
	// Bound both response size and total elapsed time, including slow partial reads.
	let mut line = Vec::new();
	while line.len() < 1024 {
		socket
			.set_read_timeout(Some(remaining(deadline)?))
			.map_err(|e| format!("setting read timeout failed: {e}"))?;
		let mut byte = [0];
		if socket.read(&mut byte).map_err(|e| io_error("reading HTTP status", e))? == 0 {
			return Err("connection closed before a complete HTTP status line".into());
		}
		line.push(byte[0]);
		if line.ends_with(b"\r\n") {
			if line.starts_with(b"HTTP/1.1 200 ") || line.starts_with(b"HTTP/1.0 200 ") {
				return Ok(());
			}
			// Debug formatting escapes control characters in untrusted response text.
			return Err(format!("expected HTTP 200, received {:?}", String::from_utf8_lossy(&line)));
		}
	}
	Err("HTTP status line exceeds 1024 bytes".into())
}

fn env(name: &str) -> Result<Option<String>, String> {
	match std::env::var(name) {
		Ok(value) => Ok(Some(value)),
		Err(std::env::VarError::NotPresent) => Ok(None),
		Err(_) => Err(format!("{name} must contain valid Unicode")),
	}
}

fn run() -> Result<(), String> {
	let config = Config::parse(
		env("REDLIB_HEALTHCHECK_HOST")?.as_deref(),
		env("REDLIB_HEALTHCHECK_PORT")?.as_deref(),
		env("PORT")?.as_deref(),
		env("REDLIB_HEALTHCHECK_TIMEOUT")?.as_deref(),
	)?;
	healthy(&config).map_err(|e| format!("GET http://{}/settings ({}s deadline): {e}", config.address, config.timeout.as_secs()))
}

fn main() {
	if let Err(error) = run() {
		eprintln!("redlib-healthcheck: {error}");
		std::process::exit(1);
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::net::TcpListener;

	fn check_response(response: &[u8]) -> Result<(), String> {
		let listener = TcpListener::bind("127.0.0.1:0").unwrap();
		let config = Config {
			address: listener.local_addr().unwrap(),
			timeout: Duration::from_secs(2),
		};
		let response = response.to_vec();
		let server = std::thread::spawn(move || {
			let (mut socket, _) = listener.accept().unwrap();
			socket.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
			let mut request = Vec::new();
			while !request.ends_with(b"\r\n\r\n") {
				let mut byte = [0];
				socket.read_exact(&mut byte).unwrap();
				request.push(byte[0]);
			}
			assert!(request.starts_with(b"GET /settings HTTP/1.1\r\n"));
			let _ = socket.write_all(&response);
		});
		let result = healthy(&config);
		server.join().unwrap();
		result
	}

	#[test]
	fn accepts_only_successful_http_status() {
		assert!(check_response(b"HTTP/1.1 200 OK\r\n\r\n").is_ok());
		assert!(check_response(b"HTTP/1.0 200 OK\r\n\r\n").is_ok());
		for status in ["500 Error", "302 Found", "403 Forbidden", "2000 Invalid"] {
			let error = check_response(format!("HTTP/1.1 {status}\r\n").as_bytes()).unwrap_err();
			assert!(error.contains(status), "{error}");
		}
		assert!(check_response(b"broken").unwrap_err().contains("connection closed"));
		assert!(check_response(&[b'x'; 1024]).unwrap_err().contains("exceeds 1024"));
	}

	#[test]
	fn configuration_defaults_and_overrides() {
		let default = Config::parse(None, None, None, None).unwrap();
		assert_eq!(default.address, "127.0.0.1:8080".parse().unwrap());
		assert_eq!(default.timeout, Duration::from_secs(5));
		assert_eq!(Config::parse(None, None, Some("9090"), None).unwrap().address.port(), 9090);
		let custom = Config::parse(Some("::1"), Some("8181"), Some("invalid-but-overridden"), Some("10")).unwrap();
		assert_eq!(custom.address, "[::1]:8181".parse().unwrap());
		assert_eq!(custom.timeout, Duration::from_secs(10));
	}

	#[test]
	fn rejects_invalid_configuration() {
		for port in ["", "0", "65536", "-1", "abc"] {
			assert!(Config::parse(None, Some(port), None, None).is_err());
			assert!(Config::parse(None, None, Some(port), None).is_err());
		}
		for timeout in ["", "0", "61", "-1", "1.5", "abc"] {
			assert!(Config::parse(None, None, None, Some(timeout)).is_err());
		}
		assert!(Config::parse(Some("localhost"), None, None, None).is_err());
	}

	#[test]
	fn reports_connection_failure() {
		// Release an ephemeral listener and verify that a refused connection is reported.
		let listener = TcpListener::bind("127.0.0.1:0").unwrap();
		let address = listener.local_addr().unwrap();
		drop(listener);
		assert!(healthy(&Config {
			address,
			timeout: Duration::from_secs(1)
		})
		.unwrap_err()
		.contains("connection failed"));
	}

	#[test]
	fn times_out_when_server_stalls() {
		let listener = TcpListener::bind("127.0.0.1:0").unwrap();
		let config = Config {
			address: listener.local_addr().unwrap(),
			timeout: Duration::from_millis(50),
		};
		let server = std::thread::spawn(move || {
			let (_socket, _) = listener.accept().unwrap();
			std::thread::sleep(Duration::from_millis(250));
		});
		let error = healthy(&config).unwrap_err();
		assert!(error.contains("timeout") || error.contains("reading HTTP status"), "{error}");
		server.join().unwrap();
	}

	#[test]
	fn partial_reads_share_one_deadline() {
		let listener = TcpListener::bind("127.0.0.1:0").unwrap();
		let config = Config {
			address: listener.local_addr().unwrap(),
			timeout: Duration::from_millis(80),
		};
		let server = std::thread::spawn(move || {
			let (mut socket, _) = listener.accept().unwrap();
			for byte in b"HTTP/1.1 200 A deliberately slow response\r\n" {
				if socket.write_all(&[*byte]).is_err() {
					break;
				}
				std::thread::sleep(Duration::from_millis(10));
			}
		});
		assert!(healthy(&config).is_err());
		server.join().unwrap();
	}

	#[test]
	fn expired_deadline_is_rejected() {
		assert!(remaining(Instant::now() - Duration::from_secs(1)).is_err());
	}
}
