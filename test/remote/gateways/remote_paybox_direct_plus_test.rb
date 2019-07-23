# frozen_string_literal: true

require 'test_helper'

class RemotePayboxDirectPlusTest < Minitest::Test
  def setup
    @gateway = PayboxDirectPlusGateway.new(fixtures(:paybox_direct_plus))
    @amount = 100
    @credit_card = credit_card('1111222233334444')
    @declined_card = credit_card('1111222233334445')
    @options = {
      order_id:       "REF#{Time.now.usec}",
      user_reference: "USER#{Time.now.usec}"
    }
  end

  def test_create_profile
    assert response = @gateway.create_payment_profile(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'The transaction was approved', response.message
    assert response.authorization =~ /\A\d{20}\z/, "Expecting numeric authorization number. Got: #{response.authorization}"
  end

  def test_create_profile_capture_and_void
    assert response = @gateway.create_payment_profile(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'The transaction was approved', response.message

    credit_card_reference = response.params['credit_card_reference']
    assert !credit_card_reference.nil?, "Got: #{response.params.inspect}"

    assert capture = @gateway.capture(@amount, response.authorization, @options)
    assert_success capture

    assert void = @gateway.void(@amount, capture.authorization, @options)
    assert_equal 'The transaction was approved', void.message
    assert_success void
  end

  def test_create_profile_and_purchase
    assert response = @gateway.create_payment_profile(@amount, @credit_card, @options)
    assert_success response

    credit_card_reference = response.params['credit_card_reference']
    assert !credit_card_reference.nil?, "Got: #{response.params.inspect}"

    @credit_card.number = nil

    assert response = @gateway.purchase(@amount, @credit_card, @options.merge(credit_card_reference: credit_card_reference))
    assert_success response
    assert_equal 'The transaction was approved', response.message
  end

  def test_failed_capture
    assert response = @gateway.capture(@amount, '', order_id: '1', user_reference: 'pipomolo')
    assert_failure response
    assert_equal 'Mandatory values missing keyword:13 Type:20', response.message, response.params.inspect
  end

  # def test_successful_purchase
  #   response = @gateway.purchase(@amount, @credit_card, @options)
  #   assert_success response
  #   assert_equal 'REPLACE WITH SUCCESS MESSAGE', response.message
  # end

  # def test_successful_purchase_with_more_options
  #   options = {
  #     order_id: '1',
  #     ip: "127.0.0.1",
  #     email: "joe@example.com"
  #   }
  #
  #   response = @gateway.purchase(@amount, @credit_card, options)
  #   assert_success response
  #   assert_equal 'REPLACE WITH SUCCESS MESSAGE', response.message
  # end

  # def test_failed_purchase
  #   response = @gateway.purchase(@amount, @declined_card, @options)
  #   assert_failure response
  #   assert_equal 'REPLACE WITH FAILED PURCHASE MESSAGE', response.message
  # end

  # def test_successful_authorize_and_capture
  #   auth = @gateway.authorize(@amount, @credit_card, @options)
  #   assert_success auth
  #
  #   assert capture = @gateway.capture(@amount, auth.authorization)
  #   assert_success capture
  #   assert_equal 'REPLACE WITH SUCCESS MESSAGE', capture.message
  # end

  # def test_failed_authorize
  #   response = @gateway.authorize(@amount, @declined_card, @options)
  #   assert_failure response
  #   assert_equal 'REPLACE WITH FAILED AUTHORIZE MESSAGE', response.message
  # end

  # def test_partial_capture
  #   auth = @gateway.authorize(@amount, @credit_card, @options)
  #   assert_success auth
  #
  #   assert capture = @gateway.capture(@amount-1, auth.authorization)
  #   assert_success capture
  # end

  # # def test_failed_capture
  # #   response = @gateway.capture(@amount, '')
  # #   assert_failure response
  # #   assert_equal 'REPLACE WITH FAILED CAPTURE MESSAGE', response.message
  # # end

  # def test_successful_refund
  #   purchase = @gateway.purchase(@amount, @credit_card, @options)
  #   assert_success purchase
  #
  #   assert refund = @gateway.refund(@amount, purchase.authorization)
  #   assert_success refund
  #   assert_equal 'REPLACE WITH SUCCESSFUL REFUND MESSAGE', refund.message
  # end

  # def test_partial_refund
  #   purchase = @gateway.purchase(@amount, @credit_card, @options)
  #   assert_success purchase
  #
  #   assert refund = @gateway.refund(@amount-1, purchase.authorization)
  #   assert_success refund
  # end

  # def test_failed_refund
  #   response = @gateway.refund(@amount, '')
  #   assert_failure response
  #   assert_equal 'REPLACE WITH FAILED REFUND MESSAGE', response.message
  # end

  # def test_successful_void
  #   auth = @gateway.authorize(@amount, @credit_card, @options)
  #   assert_success auth
  #
  #   assert void = @gateway.void(auth.authorization)
  #   assert_success void
  #   assert_equal 'REPLACE WITH SUCCESSFUL VOID MESSAGE', void.message
  # end

  # def test_failed_void
  #   response = @gateway.void('')
  #   assert_failure response
  #   assert_equal 'REPLACE WITH FAILED VOID MESSAGE', response.message
  # end

  # def test_successful_verify
  #   response = @gateway.verify(@credit_card, @options)
  #   assert_success response
  #   assert_match %r{REPLACE WITH SUCCESS MESSAGE}, response.message
  # end

  # def test_failed_verify
  #   response = @gateway.verify(@declined_card, @options)
  #   assert_failure response
  #   assert_match %r{REPLACE WITH FAILED PURCHASE MESSAGE}, response.message
  # end

  # def test_invalid_login
  #   gateway = PayboxDirectPlusGateway.new(login: '', password: '')
  #
  #   response = gateway.purchase(@amount, @credit_card, @options)
  #   assert_failure response
  #   assert_match %r{REPLACE WITH FAILED LOGIN MESSAGE}, response.message
  # end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.create_payment_profile(@amount, @credit_card, @options)
    end
    transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, transcript)
    assert_scrubbed(@credit_card.verification_value, transcript)
    assert_scrubbed(@gateway.options[:password], transcript)
  end
end
