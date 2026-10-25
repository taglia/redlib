//! Shell-free container liveness check; deliberately uses no HTTP client crates.
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

fn healthy(address: SocketAddr) -> std::io::Result<bool> {
	let timeout = Duration::from_secs(2);
	let mut socket = TcpStream::connect_timeout(&address, timeout)?;
	socket.set_read_timeout(Some(timeout))?;
	socket.set_write_timeout(Some(timeout))?;
	socket.write_all(b"GET /settings HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")?;
	// HTTP status/version is ASCII. Bound the read and accept only an exact 200 status.
	let mut prefix = [0; 13];
	socket.read_exact(&mut prefix)?;
	Ok(&prefix == b"HTTP/1.1 200 " || &prefix == b"HTTP/1.0 200 ")
}

fn main() {
	let address = SocketAddr::from(([127, 0, 0, 1], 8080));
	if !healthy(address).unwrap_or(false) {
		std::process::exit(1);
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::net::TcpListener;

	fn check_response(response: &'static [u8]) -> bool {
		let listener = TcpListener::bind("127.0.0.1:0").unwrap();
		let address = listener.local_addr().unwrap();
		let server = std::thread::spawn(move || {
			let (mut socket, _) = listener.accept().unwrap();
			socket.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
			let mut request = [0; 128];
			let _ = socket.read(&mut request).unwrap();
			socket.write_all(response).unwrap();
		});
		let result = healthy(address).unwrap_or(false);
		server.join().unwrap();
		result
	}

	#[test]
	fn accepts_only_successful_http_status() {
		assert!(check_response(b"HTTP/1.1 200 OK\r\n\r\n"));
		assert!(check_response(b"HTTP/1.0 200 OK\r\n\r\n"));
		assert!(!check_response(b"HTTP/1.1 500 Error\r\n\r\n"));
		assert!(!check_response(b"HTTP/1.1 2000 Invalid\r\n\r\n"));
		assert!(!check_response(b"broken"));
	}
}
