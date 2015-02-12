module ProMotion
  module IAP
    attr_accessor :completion_handlers

    def purchase_iap(product_id, &callback)
      iap_setup
      retrieve_iaps product_id do |products|
        products.each do |product|
          self.completion_handlers["purchase-#{product[:product_id]}"] = callback
          payment = SKPayment.paymentWithProduct(product[:product])
          SKPaymentQueue.defaultQueue.addPayment(payment)
        end
      end
    end

    def restore_iaps(product_id, &callback)
      iap_setup
      retrieve_iaps product_id do |products|
        products.each do |product|
          self.completion_handlers["restore-#{product[:product_id]}"] = callback
          SKPaymentQueue.defaultQueue.restoreCompletedTransactions
        end
      end
    end

    def retrieve_iaps(*product_ids, &callback)
      iap_setup
      self.completion_handlers["retrieve_iaps"] = callback
      @products_request = SKProductsRequest.alloc.initWithProductIdentifiers(NSSet.setWithArray(product_ids.flatten))
      @products_request.delegate = self
      @products_request.start
    end
    alias retrieve_iap retrieve_iaps

    def completion_handlers
      @completion_handlers ||= {}
    end

    # private methods

    private

    def iap_setup
      SKPaymentQueue.defaultQueue.addTransactionObserver(self)
    end

    def iap_shutdown
      SKPaymentQueue.defaultQueue.removeTransactionObserver(self)
    end

    def retrieved_iaps_handler(products, &callback)
      sk_products = products.map do |sk_product|
        {
          product_id:               sk_product.productIdentifier,
          title:                    sk_product.localizedTitle,
          description:              sk_product.localizedDescription,
          formatted_price:          formatted_iap_price(sk_product.price, sk_product.priceLocale),
          price:                    sk_product.price,
          price_locale:             sk_product.priceLocale,
          downloadable:             sk_product.isDownloadable,
          download_content_lengths: sk_product.downloadContentLengths,
          download_content_version: sk_product.downloadContentVersion,
          product:                  sk_product,
        }
      end

      callback.call(sk_products, nil) if callback.arity == 2
      callback.call(sk_products) if callback.arity < 2
    end

    def formatted_iap_price(price, price_locale)
      num_formatter = NSNumberFormatter.new
      num_formatter.setFormatterBehavior NSNumberFormatterBehaviorDefault
      num_formatter.setNumberStyle NSNumberFormatterCurrencyStyle
      num_formatter.setLocale price_locale
      num_formatter.stringFromNumber price
    end

    public

    # SKProductsRequestDelegate methods

    def productsRequest(_, didReceiveResponse:response)
      unless response.invalidProductIdentifiers.empty?
        PM.logger.error "PM::IAP Error - invalid product identifier(s) '#{response.invalidProductIdentifiers.join("', '")}' for application identifier #{NSBundle.mainBundle.infoDictionary['CFBundleIdentifier'].inspect}"
      end
      retrieved_iaps_handler(response.products, &self.completion_handlers["retrieve_iaps"])
      @products_request = nil
      self.completion_handlers["retrieve_iaps"] = nil
    end

    def request(_, didFailWithError:error)
      self.completion_handlers["retrieve_iaps"].call([], error) if self.completion_handlers["retrieve_iaps"].arity == 2
      self.completion_handlers["retrieve_iaps"].call([]) if self.completion_handlers["retrieve_iaps"].arity < 2
      @products_request = nil
      self.completion_handlers["retrieve_iaps"] = nil
    end

    # SKPaymentTransactionObserver methods

    def paymentQueue(_, updatedTransactions:transactions)
      transactions.each do |transaction|
        case transaction.transactionState
        when SKPaymentTransactionStatePurchased then iap_callback(true,  transaction)
        when SKPaymentTransactionStateRestored  then iap_callback(true,  transaction)
        when SKPaymentTransactionStateFailed
          if transaction.error.code == SKErrorPaymentCancelled
            iap_callback(nil,   transaction)
          else
            iap_callback(false, transaction)
          end
        end
      end
    end

    def iap_callback(success, transaction)
      if self.completion_handlers["purchase-#{transaction.productIdentifier}"]
        self.completion_handlers["purchase-#{transaction.productIdentifier}"].call success, transaction
        self.completion_handlers["purchase-#{transaction.productIdentifier}"] = nil
      end
      if self.completion_handlers["restore-#{transaction.productIdentifier}"]
        self.completion_handlers["restore-#{transaction.productIdentifier}"].call success, transaction
        self.completion_handlers["restore-#{transaction.productIdentifier}"] = nil
      end
      SKPaymentQueue.defaultQueue.finishTransaction(transaction)
    end

  end
end