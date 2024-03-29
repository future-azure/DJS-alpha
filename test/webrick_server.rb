
require 'webrick'
require './logo'

document_root = '../'

class WebrickServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_POST(req, res)
    res['Content-Type'] = 'text/plain'
    res.body = DJS.response(req.body)
  end
end

server = WEBrick::HTTPServer.new({
  :DocumentRoot => document_root,
  :Port => 8080,
  :BindAddress => '127.0.0.1'})
server.mount('/djs', WebrickServlet)
trap('INT') {
    server.shutdown
}

server.start

