#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'rubygems'
require 'minitest/autorun'
require 'money'
require 'mocha'
require 'yaml'
require 'active_merchant'
require File.join(File.dirname(__FILE__), '..', 'lib', 'active_merchant', 'billing', 'paybox_direct_plus_gateway')
# require 'ruby-debug'

require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/time/acts_like'

# require 'action_controller'
# require 'action_view/template'
# require 'action_dispatch/testing/test_process'
# require 'active_merchant/billing/integrations/action_view_helper'

ActiveMerchant::Billing::Base.mode = :test

require 'logger'
ActiveMerchant::Billing::Gateway.logger = Logger.new(STDOUT) if ENV['DEBUG_ACTIVE_MERCHANT'] == 'true'

# Test gateways
class SimpleTestGateway < ActiveMerchant::Billing::Gateway
end

class SubclassGateway < SimpleTestGateway
end

module ActiveMerchant
  module Assertions
    AssertionClass = defined?(Minitest) ? MiniTest::Assertion : Test::Unit::AssertionFailedError

    def assert_field(field, value)
      clean_backtrace do
        assert_equal value, @helper.fields[field]
      end
    end

    # Allows the testing of you to check for negative assertions:
    #
    #   # Instead of
    #   assert !something_that_is_false
    #
    #   # Do this
    #   assert_false something_that_should_be_false
    #
    # An optional +msg+ parameter is available to help you debug.
    def assert_false(boolean, msg = nil)
      clean_backtrace do
        assert !boolean, message(msg, "#{boolean.inspect} is not false or nil.")
      end
    end

    # A handy little assertion to check for a successful response:
    #
    #   # Instead of
    #   assert_success response
    #
    #   # DRY that up with
    #   assert_success response
    #
    # A message will automatically show the inspection of the response
    # object if things go afoul.
    def assert_success(response)
      clean_backtrace do
        assert response.success?, "Response failed: #{response.inspect}"
      end
    end

    # The negative of +assert_success+
    def assert_failure(response)
      clean_backtrace do
        assert_false response.success?, "Response expected to fail: #{response.inspect}"
      end
    end

    def assert_valid(validateable)
      clean_backtrace do
        assert validateable.valid?, 'Expected to be valid'
      end
    end

    def assert_not_valid(validateable)
      clean_backtrace do
        assert_false validateable.valid?, 'Expected to not be valid'
      end
    end

    def assert_scrubbed(unexpected_value, transcript)
      regexp = (Regexp === unexpected_value ? unexpected_value : Regexp.new(Regexp.quote(unexpected_value.to_s)))
      refute_match regexp, transcript, 'Expected the value to be scrubbed out of the transcript'
    end

  private

    def clean_backtrace
      yield
    rescue AssertionClass => e
      path = File.expand_path(__FILE__)
      raise(AssertionClass, e.message, e.backtrace.reject { |line| File.expand_path(line) =~ /#{path}/ })
    end
  end

  module Fixtures
    HOME_DIR = RUBY_PLATFORM =~ /mswin32/ ? ENV['HOMEPATH'] : ENV['HOME'] unless defined?(HOME_DIR)
    LOCAL_CREDENTIALS = File.join(HOME_DIR.to_s, '.active_merchant/fixtures.yml') unless defined?(LOCAL_CREDENTIALS)
    DEFAULT_CREDENTIALS = File.join(File.dirname(__FILE__), 'fixtures.yml') unless defined?(DEFAULT_CREDENTIALS)

    class << self
      attr_accessor :data
    end

  private

    def credit_card(number = '4242424242424242', options = {})
      defaults = {
        number:             number,
        month:              9,
        year:               Time.now.year + 1,
        first_name:         'Longbob',
        last_name:          'Longsen',
        verification_value: '123',
        brand:              'visa'
      }.update(options)

      Billing::CreditCard.new(defaults)
    end

    def check(options = {})
      defaults = {
        name:                'Jim Smith',
        routing_number:      '244183602',
        account_number:      '15378535',
        account_holder_type: 'personal',
        account_type:        'checking',
        number:              '1'
      }.update(options)

      Billing::Check.new(defaults)
    end

    def address(options = {})
      {
        name:     'Jim Smith',
        address1: '1234 My Street',
        address2: 'Apt 1',
        company:  'Widgets Inc',
        city:     'Ottawa',
        state:    'ON',
        zip:      'K1C2N6',
        country:  'CA',
        phone:    '(555)555-5555',
        fax:      '(555)555-6666'
      }.update(options)
    end

    def all_fixtures
      Fixtures.data ||= load_fixtures
    end

    def fixtures(key)
      data = all_fixtures[key] || raise(StandardError, "No fixture data was found for '#{key}'")

      data.dup
    end

    def load_fixtures
      file = File.exist?(LOCAL_CREDENTIALS) ? LOCAL_CREDENTIALS : DEFAULT_CREDENTIALS
      yaml_data = YAML.safe_load(File.read(file))
      symbolize_keys(yaml_data)

      yaml_data
    end

    def symbolize_keys(hash)
      return unless hash.is_a?(Hash)

      hash.symbolize_keys!
      hash.each { |_k, v| symbolize_keys(v) }
    end
  end
end

Minitest::Test.class_eval do
  include ActiveMerchant::Billing
  include ActiveMerchant::Assertions
  include ActiveMerchant::Fixtures

  def capture_transcript(gateway)
    transcript = StringIO.new
    gateway.class.wiredump_device = transcript

    yield

    transcript.string
  end

  def dump_transcript_and_fail(gateway, amount, credit_card, params)
    transcript = capture_transcript(gateway) do
      gateway.purchase(amount, credit_card, params)
    end

    File.open('transcript.log', 'w') { |f| f.write(transcript) }
    assert false, 'A purchase transcript has been written to transcript.log for you to test scrubbing with.'
  end
end
