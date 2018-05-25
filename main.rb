class LeadExtractor
  require 'colorize'
  require 'certified'
  require 'json'
  require 'json-prettyprint'
  require 'date'
  require_relative 'date_extend_with_quarter'
  require_relative 'asyncness'
  require_relative 'what_form'
  require 'dotenv/load'

  attr_accessor :json

  MOVING_URLS = [
    ENV['UMZUG_OFFERTE_ANFORDERN_MAIN'],
    ENV['UMZUG_OFFERTE_ANFORDERN_BRANCH'],
    ENV['UMZUG_OFFERTE_ANFORDERN_ZURICH'],
    ENV['SWISS_MOVING_QUOTES_MAIN_FORM']
  ].freeze
  CLEANING_URLS = [
    ENV['SWISS_CLEANING_QUOTES_MAIN_FORM'],
    ENV['REINIGUNGSOFFERTE_ANFORDERN'],
    ENV['REINIGUNGS_OFFERTE_ANFORDERN_MAIN']
  ].freeze

  def initialize(leads_type)
    @json = []
    @moving_urls = MOVING_URLS
    @cleaning_urls = CLEANING_URLS
    @combined_urls = MOVING_URLS + CLEANING_URLS
    @leads_type = leads_type
    raise ArgumentError, '⚠️ Invalid argument! choices: "moving" or "cleaning" or "combined"' unless %w[moving cleaning combined].any? { |word| word == leads_type.downcase }
  end

  def fetch_leads(url_type:)
    urls = instance_variable_get("@#{url_type.downcase}_urls")
    EM.run do
      urls.lazy.each { |url| create_fiber(url, urls) }
    end
  end

  def create_fiber(url, urls)
    Fiber.new do
      what_form(url)
      response = make_request_to(url)
      @json << JSON.parse(response)
      notify_done(urls.size)
    end.resume
  end

  def flatten_leads_arrays(_arrays)
    @json = @json.reduce(:concat)
  end

  def add_lead_type_to_leads
    @json.each do |lead|
      if lead['Umzug'] == ''
        lead['lead_type'] = 'UMZUG'
        lead['Umzug'].delete
      elsif lead['Reinigung'] == ''
        lead['lead_type'] = 'REINIGUNG'
        lead['Reinigung'].delete
      end
    end
  end

  def add_quarter_to_leads
    @json.each do |lead|
      lead['quarter'] ||= {}
      lead['quarter']['Q'] = Date.parse(lead['Submitted']).quarter
      lead['quarter']['year'] = Date.parse(lead['Submitted']).year
    end
  end

  def group_by_quarter
    @json = @json.group_by { |h| h['quarter'] }
  end

  def sort_by_date
    @json.each do |_keys, values|
      values.sort_by! { |key| key['Submitted'] }
    end
  end

  def shorten_dates
    @json.each do |_keys, values|
      values.each do |key|
        key['Submitted'] = Date.parse(key['Submitted']).strftime('%d.%m.%Y')
      end
    end
  end

  def print_quarters_and_values
    @json.each do |keys, values|
      print_quarter_year_size(keys, values)
      print_leads_date_range(values)
      print_bold_line
      print_leads(values, 'UMZUG')
      print_normal_line
      print_leads(values, 'REINIGUNG')
      print_bold_line
    end
  end

  def print_statistics # will change in future.
    @lead_count = []
    @json.each do |_keys, values|
      values.each do |_key, value|
        @lead_count << value
      end
    end

    # puts JSON::PrettyPrint.prettify(@json.to_json)
    puts "each request count: #{@each_array_size}".bold
    puts 'number of leads are the equal even after parsing?'.bold
    puts (@each_array_size.sum == @lead_count.size).to_s.colorize(:green).bold
    puts "total leads: #{@lead_count.size}".colorize(:yellow).bold
  end

  def clear_json
    @json = []
    puts 'Cleared! ✅'
  end

  def flow(arg = @leads_type)
    # Use Enumerable's any method and matching against the word
    raise ArgumentError, '⚠️ Invalid argument! choices: "moving" or "cleaning" or "combined"' unless %w[moving cleaning combined].any? { |word| word == arg.downcase }

    fetch_leads(url_type: arg)
    collect_arrays_sizes(@json)
    flatten_leads_arrays(@json)
    add_quarter_to_leads
    add_lead_type_to_leads
    group_by_quarter
    sort_by_date
    shorten_dates
    print_quarters_and_values
    print_statistics # will change in future
    # find_specific_leads
    clear_json
  end

  private

  def collect_arrays_sizes(arrays)
    @each_array_size = arrays.map(&:size)
  end

  def print_leads(values, lead_type)
    raise ArgumentError, '⚠️ Invalid argument! responds to: "UMZUG" or "REINIGUNG"' unless %w[UMZUG REINIGUNG].any? { |word| word == lead_type.upcase }
    values.select { |lead| lead['lead_type'] == lead_type }.each_with_index do |(key, _), index|
      id = index + 1
      puts "#{id} | #{key['Submitted']} | #{key['lead_type']} | #{key['Ticket']} | #{key['Anrede']} #{key['your-name']} #{key['Vorname']}"
    end
  end

  def print_quarter_year_size(keys, values)
    puts "Q#{keys['Q']} of #{keys['year']} Leads received: #{values.length}".colorize(:red).underline.bold
  end

  def print_leads_date_range(values)
    puts "From: #{values[0]['Submitted']} Until: #{values[-1]['Submitted']}".colorize(:white).underline.bold
  end

  def print_bold_line
    puts '-------------------------------------------------------------------'.bold
  end

  def print_normal_line
    puts '-------------------------------------------------------------------'
  end
end

if  $PROGRAM_NAME == __FILE__
  l = LeadExtractor.new 'combined'
  l.flow
end
