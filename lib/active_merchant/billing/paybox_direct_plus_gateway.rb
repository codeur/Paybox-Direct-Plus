# frozen_string_literal: true

require 'active_merchant'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayboxDirectPlusGateway < Gateway
      mattr_accessor :test_backup_url, :live_backup_url

      self.test_url        = 'https://preprod-ppps.paybox.com/PPPS.php'
      self.test_backup_url = 'https://preprod-ppps.paybox.com/PPPS.php'
      self.live_url        = 'https://ppps.paybox.com/PPPS.php'
      self.live_backup_url = 'https://ppps1.paybox.com/PPPS.php'

      self.supported_countries = ['FR']
      self.default_currency = 'EUR'
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club, :jcb]

      self.homepage_url = 'http://www.paybox.com/'
      self.display_name = 'Paybox Direct Plus'

      self.money_format = :cents

      # Payment API Version
      # 00103 for Paybox Direct
      # 00104 for Paybox Direct Plus
      API_VERSION = '00104'

      # Transactions hash
      TRANSACTIONS = {
        authorize:              '00001',
        capture:                '00002',
        purchase:               '00003',
        credit:                 '00004',
        void:                   '00005',
        verify:                 '00011',
        capture_directly:       '00012', # Capture without authorization
        refund:                 '00014',
        consultation:           '00017',
        subscriber_authorize:   '00051',
        subscriber_capture:     '00052',
        subscriber_purchase:    '00053',
        subscriber_credit:      '00054',
        subscriber_void:        '00055',
        subscriber_create:      '00056',
        subscriber_update:      '00057',
        subscriber_destroy:     '00058',
        force_capture_directly: '00061'
      }.freeze

      CURRENCY_CODES = {
        'AUD' => '036',
        'CAD' => '124',
        'CZK' => '203',
        'DKK' => '208',
        'HKD' => '344',
        'ICK' => '352',
        'JPY' => '392',
        'NOK' => '578',
        'SGD' => '702',
        'SEK' => '752',
        'CHF' => '756',
        'GBP' => '826',
        'USD' => '840',
        'EUR' => '978'
      }.freeze

      # STANDARD_ERROR_CODE_MAPPING = {
      #   '00000' => STANDARD_ERROR_CODE[], # Opération réussie.
      #   '00001' => STANDARD_ERROR_CODE[], # La connexion au centre d’autorisation a échoué ou une erreur interne est survenue. Dans ce cas, il est souhaitable de faire une tentative sur le site secondaire : ppps1.paybox.com.
      #   "'001XX" # Paiement refusé par le centre d’autorisation.[voir§9.1.1Réseaux CB, Visa, Mastercard, American Express et Diners]En cas d’autorisation de la transaction par le centre d’autorisation de la banque, le résultat “00100” sera en fait remplacé directement par “00000”.
      #   '00002' => STANDARD_ERROR_CODE[], # Une erreur de cohérence est survenue.
      #   '00003' => STANDARD_ERROR_CODE[], # Erreur Paybox. Dans ce cas, il est souhaitable de faire une tentative sur le site secondaire : ppps1.paybox.com.
      #   '00004' => STANDARD_ERROR_CODE[:invalid_number], # Numéro de porteur invalide.
      #   '00005' => STANDARD_ERROR_CODE[], # Numéro de question invalide.
      #   '00006' => STANDARD_ERROR_CODE[], # Accès refusé ou site / rang incorrect.
      #   '00007' => STANDARD_ERROR_CODE[], # Date invalide.
      #   '00008' => STANDARD_ERROR_CODE[:invalid_expiry_date], # Date de fin de validité incorrecte.
      #   '00009' => STANDARD_ERROR_CODE[], # Type d’opération invalide.
      #   '00010' => STANDARD_ERROR_CODE[], # Devise inconnue.
      #   '00011' => STANDARD_ERROR_CODE[], # Montant incorrect.
      #   '00012' => STANDARD_ERROR_CODE[], # Référence commande invalide.
      #   '00013' => STANDARD_ERROR_CODE[], # Cette version n’est plus soutenue.
      #   '00014' => STANDARD_ERROR_CODE[], # Trame reçue incohérente.
      #   '00015' => STANDARD_ERROR_CODE[], # Erreur d’accès aux données précédemment référencées.
      #   '00016' => STANDARD_ERROR_CODE[], # Abonné déjà existant (inscription nouvel abonné).
      #   '00017' => STANDARD_ERROR_CODE[], # Abonné inexistant.
      #   '00018' => STANDARD_ERROR_CODE[], # Transaction non trouvée (question du type 11).
      #   # '00019' => STANDARD_ERROR_CODE[], # Réservé.
      #   '00020' => STANDARD_ERROR_CODE[:invalid_cvc], # Cryptogramme visuel non présent.
      #   '00021' => STANDARD_ERROR_CODE[:card_declined], # Carte non autorisée.
      #   '00022' => STANDARD_ERROR_CODE[], # Plafond atteint.
      #   '00023' => STANDARD_ERROR_CODE[], # Porteur déjà passé aujourd’hui.
      #   '00024' => STANDARD_ERROR_CODE[], # Code pays filtré pour ce commerçant.
      #   '00026' => STANDARD_ERROR_CODE[], # Code activité incorrect.
      #   '00040' => STANDARD_ERROR_CODE[], # Porteur enrôlé mais non authentifié.
      #   '00097' => STANDARD_ERROR_CODE[], # Timeout de connexion atteint.
      #   '00098' => STANDARD_ERROR_CODE[], # Erreur de connexion interne.
      #   '00099' => STANDARD_ERROR_CODE[], # Incohérence entre la question et la réponse. Refaire une nouvelle tentative ultérieurement.
      # }.freeze

      ALREADY_EXISTING_PROFILE_CODES = ['00016'].freeze
      UNKNOWN_PROFILE_CODES = ['00017'].freeze
      SUCCESS_CODES = ['00000'].freeze
      UNAVAILABILITY_CODES = %w[00001 00017 00097 00098].freeze
      FRAUD_CODES = %w[00102 00104 00105 00134 00138 00141 00143 00156 00157 00159].freeze
      SUCCESS_MESSAGE = 'The transaction was approved'
      FAILURE_MESSAGE = 'The transaction failed'

      def initialize(options = {})
        requires!(options, :login, :password)
        @site = options[:login].to_s[0, 7]
        @rang = options[:login].to_s[7..-1]
        @cle  = options[:password]
        super
      end

      def purchase(money, payment, options = {})
        requires!(options, :credit_card_reference, :user_reference)
        post = {}
        add_invoice(post, options)
        add_credit_card(post, payment, options)
        add_user_reference(post, options)
        add_test_error_code(post, options)
        commit('subscriber_purchase', money, post)
      end

      def authorize(money, payment, options = {})
        requires!(options, :user_reference)
        post = {}
        add_invoice(post, options)
        add_credit_card(post, payment, options)
        add_user_reference(post, options)
        add_test_error_code(post, options)

        commit('subscriber_authorize', money, post)
      end

      def capture(money, authorization, options = {})
        requires!(options, :order_id, :user_reference)
        post = {}
        add_invoice(post, options)
        add_reference(post, authorization)
        add_user_reference(post, options)
        add_test_error_code(post, options)
        commit('subscriber_capture', money, post)
      end

      def refund(money, authorization, options = {})
        post = {}
        add_invoice(post, options)
        add_reference(post, authorization)
        add_user_reference(post, options)
        commit('refund', money, post)
      end

      def void(money, authorization, options = {})
        # def void(authorization, options = {})
        requires!(options, :order_id, :user_reference)
        post = {}
        add_invoice(post, options)
        add_reference(post, authorization)
        add_user_reference(post, options)
        post[:porteur] = '000000000000000'
        post[:dateval] = '0000'
        commit('subscriber_void', money, post)
      end

      def verify(credit_card, options = {})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def credit(money, identification, options = {})
        post = {}
        add_invoice(post, options)
        add_reference(post, identification)
        add_user_reference(post, options)
        add_test_error_code(post, options)
        commit('subscriber_credit', money, post)
      end

      def payment_profiles_supported?
        true
      end

      def create_payment_profile(money, credit_card, options = {})
        requires!(options, :user_reference)
        post = {}
        add_invoice(post, options)
        add_credit_card(post, credit_card, options)
        add_user_reference(post, options)
        add_test_error_code(post, options)
        commit('subscriber_create', money, post)
      end

      def update_payment_profile(money, credit_card, options = {})
        post = {}
        add_credit_card(post, credit_card, options)
        add_user_reference(post, options)
        add_test_error_code(post, options)
        commit('subscriber_update', money, post)
      end

      def destroy_payment_profile(money, options)
        post = {}
        add_user_reference(post, options)
        add_test_error_code(post, options)
        commit('subscriber_destroy', money, post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript
          .gsub(/\b(CLE|PORTEUR|CVV|DATENAISS)=\w+/, '\1=[FILTERED]')
      end

    private

      def add_invoice(post, options)
        post[:reference] = options[:order_id]
      end

      def add_credit_card(post, credit_card, options = {})
        post[:porteur] = options[:credit_card_reference] || credit_card.number
        post[:dateval] = expdate(credit_card)
        post[:cvv] = credit_card.verification_value if credit_card.verification_value?
      end

      def add_user_reference(post, options)
        post[:refabonne] = options[:user_reference]
      end

      def add_reference(post, identification)
        post[:numappel] = identification[0, 10]
        post[:numtrans] = identification[10, 10]
      end

      def add_test_error_code(post, options)
        post[:errorcodetest] = options[:errorcodetest] if options[:errorcodetest]
      end

      def parse(body)
        body.encode!('UTF-8', 'ISO8859-1')
        results = {}
        body.split(/&/).each do |pair|
          key, val = pair.split(/=/)
          results[key.downcase.to_sym] = CGI.unescape(val) if val
        end
        results[:credit_card_reference] = results[:porteur] if results[:porteur]
        results
      end

      def commit(action, money = nil, parameters = nil)
        parameters[:montant] = ('0000000000' + (money ? amount(money) : ''))[-10..-1]
        parameters[:devise] = CURRENCY_CODES[options[:currency] || currency(money)]
        url = (test? ? test_url : live_url)
        response = parse(ssl_post(url, post_data(action, parameters)))
        if service_unavailable?(response)
          backup_url = (test? ? test_backup_url : live_backup_url)
          response = parse(ssl_post(backup_url, post_data(action, parameters)))
        end
        success = success_from(response)
        Response.new(
          success,
          message_from(response),
          response,
          # response.merge(
          #   timestamp: parameters[:dateq],
          #   # sent_params: parameters.delete_if { |key, _value| %w[porteur dateval cvv].include?(key.to_s) }
          #   # query:     request_data
          # ),
          test:          test?,
          authorization: response[:numappel].to_s + response[:numtrans].to_s,
          fraud_review:  fraud_review?(response),
          error_code:    success ? nil : response[:codereponse]
        )
      end

      def success_from(response)
        SUCCESS_CODES.include?(response[:codereponse])
      end

      def fraud_review?(response)
        FRAUD_CODES.include?(response[:codereponse])
      end

      def service_unavailable?(response)
        UNAVAILABILITY_CODES.include?(response[:codereponse])
      end

      def unknown_customer_profile?(response)
        UNKNOWN_PROFILE_CODES.include?(response[:codereponse])
      end

      def already_existing_customer_profile?(response)
        ALREADY_EXISTING_PROFILE_CODES.include?(response[:codereponse])
      end

      def message_from(response)
        success_from(response) ? SUCCESS_MESSAGE : (response[:commentaire] || FAILURE_MESSAGE)
      end

      def post_data(action, parameters = {})
        parameters.update(
          version:     API_VERSION,
          type:        TRANSACTIONS[action.to_sym],
          dateq:       Time.now.strftime('%d%m%Y%H%M%S'),
          numquestion: unique_id(parameters[:reference]),
          site:        @site,
          rang:        @rang,
          cle:         @cle,
          pays:        '',
          archivage:   parameters[:reference],
          activite:    '027'
        )

        query = parameters.collect { |key, value| "#{key.to_s.upcase}=#{CGI.escape(value.to_s)}" }.join('&')
        # Rails.logger.info "\n***************************"
        # Rails.logger.debug "********** POST DATA IN PAYBOX PLUS ***********"
        # Rails.logger.debug "*** Parameters for post data:"
        # Rails.logger.debug "#{query.inspect}"
        # Rails.logger.info "*****************************"
        query
      end

      def unique_id(seed = 0)
        randkey = "#{seed.hash}#{Time.now.usec}".to_i % 2_147_483_647 # Max paybox value for the question number

        "0000000000#{randkey}"[-10..-1]
      end

      def expdate(credit_card)
        year  = Kernel.format('%.4i', credit_card.year)
        month = Kernel.format('%.2i', credit_card.month)

        "#{month}#{year[-2..-1]}"
      end
    end
  end
end
