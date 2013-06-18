# encoding: utf-8
require 'rubygems'
require 'appium_lib'
require 'chronic_duration'
require 'minitest/autorun' # requires minitest-4.7.4
require 'minitest/reporters' # Format the report

# for Sauce Labs reporting
require 'rest_client' # https://github.com/archiloque/rest-client
require 'json' # for .to_json

# https://github.com/banister/method_source
# gem install method_source
require 'method_source' # for .source

$passed = true

# Report passed status to Sauce and quit the driver.
def update_sauce opts
  # must use selenium-webdriver (2.32.1) or better for .session_id
  id = session_id
  driver_quit

  if !sauce_username.nil? && !sauce_access_key.nil?
    url = "https://#{sauce_username}:#{sauce_access_key}@saucelabs.com/rest/v1/#{sauce_username}/jobs/#{id}"
    puts "Posting passed result #{$passed} to Sauce"
    json = { 'passed' => opts[:passed] }.to_json
    # Keep trying until passed is set correctly. Give up after 30 seconds.
    wait do
      response = RestClient.put url, json, :content_type => :json, :accept => :json
      response = JSON.parse(response)
      puts "Response #{response}"

      # Check that the server responded with the right value.
      response['passed'] == $passed
    end
  end
end

# Run tests in order
class MiniTest::Unit::TestCase
  def self.test_order; :alpha end
end

class MiniTest::Reporters::ProgressReporter::Progress
  def show *args; end
  def close; end
  def wipe; end
  def scope; end
end

class MiniTest::Reporters::ProgressReporter
  # no power bar
  def initialize(options = {})
    @detailed_skip = options.fetch(:detailed_skip, true)
    @progress = Progress.new
  end
end

# rename test, change end message.
# https://github.com/CapnKernul/minitest-reporters/blob/master/lib/minitest/reporters/progress_reporter.rb
class MiniTest::Reporters::ProgressReporter
  def failure(suite, test, test_runner)
    wipe
    print(red { 'FAIL' })
    print_test_with_time(suite, test)
    puts
    print_info(test_runner.exception, false)
    puts
    $passed = false # set global passed
    exit 1 # exit at first fail
  end
  def error(suite, test, test_runner)
    test = test.to_s.sub(/test_\d+_/, '').to_sym
    wipe
    print(red { 'ERROR' })
    print_test_with_time(suite, test)
    puts
    print_info(test_runner.exception)
    $passed = false # set global passed
    exit 1 # exit at first fail
  end
  def after_suites(suites, type)
    @progress.close if @progress

    total_time = Time.now - runner.suites_start_time
    # puts "Total time: #{total_time}"
    wipe if @progress
    puts
    puts "Finished in #{ChronicDuration.output(total_time.round) || '0s'}"
    tests = runner.test_count
    asserts = runner.assertion_count
    fails = runner.failures
    errors = runner.errors
    skips = runner.skips
    # Store pass/fail result and send to Sauce Labs
    $passed = false if fails > 0 || errors > 0
    out = ''
    out += ("%d test#{tests == 1 ? '' : 's'}#{(asserts == fails && fails == errors && errors == skips && skips == 0) ? '' : ', '}" % [tests])
    out += ('%d assertions, ' % [runner.assertion_count]) unless asserts == 0
    out += (red { '%d failures, ' } % [runner.failures]) unless fails == 0
    out += (red { "%d error#{runner.errors == 1 ? '' : 's'}#{skips ? '' : ', '}" } % [errors]) unless errors == 0
    out += (yellow { '%d skips' } % runner.skips) unless skips == 0
    out = out.strip.gsub(/,\w*$/, '')
    puts out
    puts
  end
end

MiniTest::Reporters.use! MiniTest::Reporters::ProgressReporter.new

# Alter '# Run options:' from minitest-reports
# https://github.com/CapnKernul/minitest-reporters/blob/master/lib/minitest/reporter_runner.rb#L28
class MiniTest::ReporterRunner < MiniTest::Unit
  def _run_suites(suites, type)
    # test_order = @help.match /\-\-seed (\d+)/
    # '# Run options: --seed 10181' => 'test order: 10181'
    # $stdout.puts "test order: #{test_order[1]}" if test_order
    @suites_start_time = Time.now
    count_tests!(suites, type)
    trigger_callback(:before_suites, suites, type)
    super(suites, type)
  ensure
    trigger_callback(:after_suites, suites, type)
  end

  # Silence run options
  def _run args = []
    args = process_args args
    self.options.merge! args

    self.class.plugins.each do |plugin|
      send plugin
      break unless report.empty?
    end

    return failures + errors if self.test_count > 0 # or return nil...
  rescue Interrupt
    abort 'Interrupted'
  end
end

# prevent undefined method
class MiniTest::Spec
  def after_last_method; end
  def before_first_method; end
end

class MiniTest::Spec < MiniTest::Unit::TestCase
  module DSL
    # DSL accepts a block which defines a method.
    # The method is called later.
    # after_last DSL defines the after_last_method
    # which is invoked on a test case.
    def after_last &block
      define_method 'after_last_method' do
        self.instance_eval &block
      end
    end

    def before_first &block
      define_method 'before_first_method' do
        self.instance_eval &block
      end
    end
  end
end

class MiniTest::Unit
  def _run_suites suites, type
    suites.map do |suite|
      puts
      puts "Running #{suite}"
      puts
      suite.test_methods.each do |test_name|
        test_method = suite.instance_method(test_name)
        if test_method.respond_to? :source
          src = test_method.source
        else
          next
        end

        next unless src.kind_of? String

        ary = src.split "\n"
        # this may break code that spans more than one line
        carry_over = ''
        carry_over_puts = ''
        center = ary[1..-2].map do |line|
          printed_line = line.strip
          # transform \n into \\n so it's printed properly by puts
          printed_line = printed_line.gsub /\\/, '\\' * 4
          result = "puts %(#{printed_line})\n#{line}"

          begin
            # chop off anything after '#'
            # puts "Line: #{line}" if !carry_over.empty?
            # check syntax will be nil if the line is just a comment
            check_syntax = line.split('#').first
            eval 'lambda {' + check_syntax + '}' if check_syntax
            # syntax is ok. prepend carry over
            result = carry_over_puts + carry_over + "\n" + result
            carry_over = ''
            carry_over_puts = ''
          rescue SyntaxError
            # invalid syntax, carry over next line
            # puts "-- Adding to carry over before: #{carry_over}"
            carry_over += "\n" + line
            carry_over_puts += "\n" + "puts %(#{printed_line})"
            # puts "-- Adding to carry over after: #{carry_over}"
            result = ''
          end
          # puts "Result is: #{result}" if result.include? 'password'
          result#.gsub!('puts %()', '') # remove empty puts
        end
        # must use define method for test names with spaces.
        rewrite = ["define_method(%Q(#{test_name})) do\n", center.join("\n"), ary.last].join "\n"
        # $stdout.puts ' --- rewriting'
        # $stdout.puts rewrite
        # $stdout.puts ' --- rewrite complete'
        # undefine the existing test name
        # public_instance_methods
        #$stdout.puts 'suite.class_eval { undef ' + test_name + ' }'
        # undef old test before defining new test
        # $stdout.puts "undef: #{test_name}"
        eval 'suite.class_eval { undef :"' + test_name + '" }'
        # adjust spec count
        suite.instance_variable_set(:@specs, suite.instance_variable_get(:@specs) - 1)
        # define new method
        # $stdout.puts "def: #{rewrite.split("\n").first}"
        suite.instance_eval( rewrite )
      end
      method_instance = suite.new(suite.test_methods.first)
      method_instance.before_first_method
      result = _run_suite suite, type
      # suite isn't an instance that contains 'after_last_method'
      # create test instance and invoke after_last_method
      method_instance.after_last_method
      result
    end
  end
end

# alias t to it
class MiniTest::Spec < MiniTest::Unit::TestCase
  module DSL
    alias_method :t, :it
  end
end

module MiniTest::Reporter
  def verbose?; true end
end

module MiniTest::Reporter
  def before_test(suite, test)
    puts
    # 'test_0002_::Appium::DATE' => ::Appium::DATE | version.rb | 2
    test_number = test.match(/test_(\d+)_/)[1].to_i
    test_str = test.split(/_\d+_/).last
    puts ANSI.cyan { "#{test_str} | #{suite.to_s.gsub('::', ' ')} | #{test_number}" }
  end
end

=begin
#
# Add after to each test case
#
class MiniTest::Unit::TestCase
  def before_teardown
    mobile :reset
  end
end
=end