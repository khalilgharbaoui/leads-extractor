# this grabs the form name from the url and might be useful.
def what_form(url)
  url_hash = CGI::parse(url)
  puts "Checking: #{url_hash['form']}"
end
