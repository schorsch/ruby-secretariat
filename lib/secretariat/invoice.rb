=begin
Copyright Jan Krutisch

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
=end

require 'bigdecimal'

module Secretariat
  Invoice = Struct.new("Invoice",
    :id,
    :issue_date,
    :seller,
    :buyer,
    :line_items,
    :currency_code,
    :payment_type,
    :payment_text,
    :payment_iban,
    :tax_category,
    :tax_percent,
    :tax_amount,
    :tax_reason,
    :basis_amount,
    :grand_total_amount,
    :due_amount,
    :paid_amount,
    :buyer_reference,
    :payment_description,
    :payment_status,
    :payment_due_date,

    keyword_init: true
  ) do


    def errors
      @errors
    end

    def tax_reason_text
      tax_reason || TAX_EXEMPTION_REASONS[tax_category]
    end

    def tax_category_code(version: 2)
      if version == 1
        return TAX_CATEGORY_CODES_1[tax_category] || 'S'
      end
      TAX_CATEGORY_CODES[tax_category] || 'S'
    end

    def payment_code
      PAYMENT_CODES[payment_type] || '1'
    end

    def valid?
      @errors = []
      tax = BigDecimal(tax_amount)
      basis = BigDecimal(basis_amount)
      calc_tax = basis * BigDecimal(tax_percent) / BigDecimal(100)
      calc_tax = calc_tax.round(2)
      if tax != calc_tax
        @errors << "Tax amount and calculated tax amount deviate: #{tax} / #{calc_tax}"
        return false
      end
      grand_total = BigDecimal(grand_total_amount)
      calc_grand_total = basis + tax
      if grand_total != calc_grand_total
        @errors << "Grand total amount and calculated grand total amount deviate: #{grand_total} / #{calc_grand_total}"
        return false
      end
      line_item_sum = line_items.inject(BigDecimal(0)) do |m, item|
        m + BigDecimal(item.charge_amount)
      end
      if line_item_sum != basis
        @errors << "Line items do not add up to basis amount #{line_item_sum} / #{basis}"
        return false
      end
      return true
    end


    def namespaces

        {
          'xmlns:qdt' => 'urn:un:unece:uncefact:data:standard:QualifiedDataType:100',
          'xmlns:ram' => 'urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100',
          'xmlns:udt' => 'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100',
          'xmlns:rsm' => 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100',
          'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance'
        }
    end

    def to_xml(version: 2, skip_validation: false, mode: :zugferd)
      if version < 2 || version > 3
        raise 'Unsupported Document Version'
      end
      if mode != :zugferd && mode != :xrechnung
        raise 'Unsupported Document Mode'
      end

      if !skip_validation && !valid?
        raise ValidationError.new("Invoice is invalid", errors)
      end

      builder = Nokogiri::XML::Builder.new do |xml|

        xml['rsm'].CrossIndustryInvoice(namespaces) do
          xml['rsm'].ExchangedDocumentContext do
            if version == 3 && mode == :xrechnung
              xml['ram'].BusinessProcessSpecifiedDocumentContextParameter do
                xml['ram'].ID 'urn:fdc:peppol.eu:2017:poacc:billing:01:1.0'
              end
            end
            xml['ram'].GuidelineSpecifiedDocumentContextParameter do
              version_id ='urn:cen.eu:en16931:2017'
              if mode == :xrechnung
                version_id += '#compliant#urn:xoev-de:kosit:standard:xrechnung_2.3' if version == 2
                version_id += '#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0' if version == 3
              end
              xml['ram'].ID version_id
            end
          end

          xml['rsm'].ExchangedDocument do
            xml['ram'].ID id
            xml['ram'].TypeCode '380' # TODO: make configurable
            xml['ram'].IssueDateTime do
              xml['udt'].DateTimeString(format: '102') do
                xml.text(issue_date.strftime("%Y%m%d"))
              end
            end
          end

          xml['rsm'].SupplyChainTradeTransaction do

            if version >= 2
              line_items.each_with_index do |item, i|
                item.to_xml(xml, i + 1, version: version, skip_validation: skip_validation) # one indexed
              end
            end

            xml['ram'].ApplicableHeaderTradeAgreement do
              if version >= 2 && !buyer_reference.nil?
                xml['ram'].BuyerReference do
                  xml.text(buyer_reference)
                end
              end
              xml['ram'].SellerTradeParty do
                seller.to_xml(xml, version: version)
              end
              xml['ram'].BuyerTradeParty do
                buyer.to_xml(xml, version: version)
              end
            end

            xml['ram'].ApplicableHeaderTradeDelivery do
              if version >= 2
                xml['ram'].ShipToTradeParty do
                  buyer.to_xml(xml, exclude_tax: true, version: version)
                end
              end
              xml['ram'].ActualDeliverySupplyChainEvent do
                xml['ram'].OccurrenceDateTime do
                  xml['udt'].DateTimeString(format: '102') do
                    xml.text(issue_date.strftime("%Y%m%d"))
                  end
                end
              end
            end

            xml['ram'].ApplicableHeaderTradeSettlement do
              xml['ram'].InvoiceCurrencyCode currency_code
              xml['ram'].SpecifiedTradeSettlementPaymentMeans do
                xml['ram'].TypeCode payment_code
                xml['ram'].Information payment_text
                if payment_iban && payment_iban != ''
                  xml['ram'].PayeePartyCreditorFinancialAccount do
                    xml['ram'].IBANID payment_iban
                  end
                end
              end
              # convert to each tax
              xml['ram'].ApplicableTradeTax do

                Helpers.currency_element(xml, 'ram', 'CalculatedAmount', tax_amount, currency_code, add_currency: version == 1)
                xml['ram'].TypeCode 'VAT'
                if tax_reason_text && tax_reason_text != ''
                  xml['ram'].ExemptionReason tax_reason_text
                end
                Helpers.currency_element(xml, 'ram', 'BasisAmount', basis_amount, currency_code, add_currency: version == 1)
                xml['ram'].CategoryCode tax_category_code(version: version)

                xml['ram'].RateApplicablePercent Helpers.format(tax_percent)
              end

              xml['ram'].SpecifiedTradePaymentTerms do
                if payment_status == 'unpaid'
                  xml['ram'].Description payment_description
                  xml['ram'].DueDateDateTime do
                    xml['udt'].DateTimeString(format: '102') do
                      xml.text(payment_due_date ? payment_due_date.strftime('%Y%m%d') : nil)
                    end
                  end
                else
                  xml['ram'].Description payment_status ? payment_status.capitalize : nil
                end
              end

              xml['ram'].SpecifiedTradeSettlementHeaderMonetarySummation do
                Helpers.currency_element(xml, 'ram', 'LineTotalAmount', basis_amount, currency_code, add_currency: version == 1)
                # TODO: Fix this!
                Helpers.currency_element(xml, 'ram', 'ChargeTotalAmount', BigDecimal(0), currency_code, add_currency: version == 1)
                Helpers.currency_element(xml, 'ram', 'AllowanceTotalAmount', BigDecimal(0), currency_code, add_currency: version == 1)
                Helpers.currency_element(xml, 'ram', 'TaxBasisTotalAmount', basis_amount, currency_code, add_currency: version == 1)
                Helpers.currency_element(xml, 'ram', 'TaxTotalAmount', tax_amount, currency_code, add_currency: true)
                Helpers.currency_element(xml, 'ram', 'GrandTotalAmount', grand_total_amount, currency_code, add_currency: version == 1)
                Helpers.currency_element(xml, 'ram', 'TotalPrepaidAmount', paid_amount, currency_code, add_currency: version == 1)
                Helpers.currency_element(xml, 'ram', 'DuePayableAmount', due_amount, currency_code, add_currency: version == 1)
              end
            end

          end
        end
      end
      builder.to_xml
    end
  end
end
