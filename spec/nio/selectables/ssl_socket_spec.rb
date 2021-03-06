require 'spec_helper'
require 'openssl'

describe OpenSSL::SSL::SSLSocket, :if => RUBY_VERSION >= "1.9.0" do
  let(:tcp_port) { 34567 }

  let(:ssl_key) { OpenSSL::PKey::RSA.new(1024) }

  let(:ssl_cert) do
    name = OpenSSL::X509::Name.new([%w[CN localhost]])
    OpenSSL::X509::Certificate.new.tap do |cert|
      cert.version = 2
      cert.serial = 1
      cert.issuer = name
      cert.subject = name
      cert.not_before = Time.now
      cert.not_after = Time.now + (365 * 24 *60 *60)
      cert.public_key = ssl_key.public_key

      cert.sign(ssl_key, OpenSSL::Digest::SHA1.new)
    end
  end

  let(:ssl_server_context) do
    OpenSSL::SSL::SSLContext.new.tap do |ctx|
      ctx.cert = ssl_cert
      ctx.key = ssl_key
    end
  end

  let :readable_subject do
    server = TCPServer.new("localhost", tcp_port)
    client = TCPSocket.open("localhost", tcp_port)
    peer = server.accept

    ssl_peer = OpenSSL::SSL::SSLSocket.new(peer, ssl_server_context)
    ssl_peer.sync_close = true

    ssl_client = OpenSSL::SSL::SSLSocket.new(client)
    ssl_client.sync_close = true

    # SSLSocket#connect and #accept are blocking calls.
    thread = Thread.new { ssl_client.connect }

    ssl_peer.accept
    ssl_peer << "data"

    thread.join
    pending "Failed to produce a readable SSL socket" unless select([ssl_client], [], [], 0)

    ssl_client
  end

  let :unreadable_subject do
    server = TCPServer.new("localhost", tcp_port + 1)
    client = TCPSocket.new("localhost", tcp_port + 1)
    peer = server.accept

    ssl_peer = OpenSSL::SSL::SSLSocket.new(peer, ssl_server_context)
    ssl_peer.sync_close = true

    ssl_client = OpenSSL::SSL::SSLSocket.new(client)
    ssl_client.sync_close = true

    # SSLSocket#connect and #accept are blocking calls.
    thread = Thread.new { ssl_client.connect }
    ssl_peer.accept
    thread.join

    pending "Failed to produce an unreadable socket" if select([ssl_client], [], [], 0)
    ssl_client
  end

  let :writable_subject do
    server = TCPServer.new("localhost", tcp_port + 2)
    client = TCPSocket.new("localhost", tcp_port + 2)
    peer = server.accept

    ssl_peer = OpenSSL::SSL::SSLSocket.new(peer, ssl_server_context)
    ssl_peer.sync_close = true

    ssl_client = OpenSSL::SSL::SSLSocket.new(client)
    ssl_client.sync_close = true

    # SSLSocket#connect and #accept are blocking calls.
    thread = Thread.new { ssl_client.connect }

    ssl_peer.accept
    thread.join

    ssl_client
  end

  let :unwritable_subject do
    server = TCPServer.new("localhost", tcp_port + 3)
    client = TCPSocket.open("localhost", tcp_port + 3)
    peer = server.accept

    ssl_peer = OpenSSL::SSL::SSLSocket.new(peer, ssl_server_context)
    ssl_peer.sync_close = true

    ssl_client = OpenSSL::SSL::SSLSocket.new(client)
    ssl_client.sync_close = true

    # SSLSocket#connect and #accept are blocking calls.
    thread = Thread.new { ssl_client.connect }

    ssl_peer.accept
    thread.join

    begin
      _, writers = select [], [ssl_client], [], 0
      count = ssl_client.write_nonblock "X" * 1024
      count.should_not == 0
    rescue IO::WaitReadable, IO::WaitWritable
      pending "SSL will report writable but not accept writes"
      raise if(writers.include? ssl_client)
    end while writers and writers.include? ssl_client

    # I think the kernel might manage to drain its buffer a bit even after
    # the socket first goes unwritable. Attempt to sleep past this and then
    # attempt to write again
    sleep 0.1

    # Once more for good measure!
    begin
#        ssl_client.write_nonblock "X" * 1024
      loop { ssl_client.write_nonblock "X" * 1024 }
    rescue OpenSSL::SSL::SSLError
    end

    # Sanity check to make sure we actually produced an unwritable socket
#      if select([], [ssl_client], [], 0)
#        pending "Failed to produce an unwritable socket"
#      end

    ssl_client
  end

  let :pair do
    pending "figure out why newly created sockets are selecting readable immediately"

    server = TCPServer.new("localhost", tcp_port + 4)
    client = TCPSocket.open("localhost", tcp_port + 4)
    peer = server.accept

    ssl_peer = OpenSSL::SSL::SSLSocket.new(peer, ssl_server_context)
    ssl_peer.sync_close = true

    ssl_client = OpenSSL::SSL::SSLSocket.new(client)
    ssl_client.sync_close = true

    # SSLSocket#connect and #accept are blocking calls.
    thread = Thread.new { ssl_client.connect }
    ssl_peer.accept

    [thread.value, ssl_peer]
  end

  it_behaves_like "an NIO selectable"
  it_behaves_like "an NIO selectable stream"
end
