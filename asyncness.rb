# Depends on gems eventmachine, em-http-request,
# and em-resolv-replace (for # async DNS)

require 'eventmachine'
require 'em-http'
require 'fiber'
require 'em-resolv-replace'

def make_request_to(url)
  connection = EventMachine::HttpRequest.new(url)
  request = connection.get

  # Stores the fiber on which the request was made
  original_fiber = Fiber.current

  # This block is going to be executed when the request finishes
  request.callback do

    # When the request finishes, we wake the fiber with Fiber#resume. The
    # argument we pass here (the result of the request) will be the return
    # value of Fiber.yield
    original_fiber.resume(request.response)
  end

  request.errback do
    puts "Ooops :("
    EM.stop
  end

  # This will make the fiber be 'suspended' until a #resume call is issued
  # against it. The argument given to #resume will be the return value here.
  return Fiber.yield
end

# Simple counter to know when to exit the program. A web server probably
# wouldnt' have something like this :)
def notify_done(number)
  @complete_requests ||= 0
  @complete_requests += 1
  #NOTE: depending on a number... variable... not so smart.
  if @complete_requests == number
    EM.stop
  end
  puts "done? #{@complete_requests}"
  puts
end

# rack-fiber-pool does something similar to this: It puts each request on a
# different fiber. When you Fiber.yield (either directly or with a library
# such as em-synchrony doing that for you), the server goes on and handles the
# next request on the line. Then, as the fibers get awaken (from the database
# driver, or from an external http call, like on this example), the server
# continues processing the original request.

#NOTE
# EM.run do
#   # We put inside the lines that depend on each other on the same fiber. For
#   # instance: printing the response depends on the response arriving.
#   Fiber.new {
#     puts 'Making google request'
#
#     # This call is going to suspend the fiber until the request returns.
#     google_response = make_request_to("http://google.com")
#
#     puts
#     puts "google response:"
#     puts google_response.lines.take(10)
#
#     notify_done
#   }.resume
#
#   Fiber.new {
#     puts 'Making twitter request'
#
#     # Since the previous fiber is suspended as soon as the 'google' request is
#     # made, the 'twitter' request is made before the previous one returns.
#     twitter_response = make_request_to("http://twitter.com")
#
#     puts
#     puts "twitter response:"
#     puts twitter_response.lines.take(10)
#
#     notify_done
#   }.resume
# end
