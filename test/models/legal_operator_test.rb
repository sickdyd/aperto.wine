require "test_helper"

# The operator identity block published on the legal pages. Every field is
# public information, so the risk here is not disclosure — it is publishing
# *someone else's* details (a fork, a staging copy) or publishing an
# incomplete block that reads as finished. Hence: values come from the
# environment, and "unset" is a state the object reports rather than hides.
class LegalOperatorTest < ActiveSupport::TestCase
  COMPLETE = {
    name: "Aperto Wine S.r.l.",
    address: "Via Roma 1, 20121 Milano (MI), Italia",
    email: "legal@aperto.wine",
    phone: "+39 02 1234567",
    vat_number: "IT01234567890",
    rea_number: "MI-1234567"
  }.freeze

  test "exposes every configured field" do
    operator = LegalOperator.new(**COMPLETE)

    LegalOperator::FIELDS.each do |field|
      assert_equal COMPLETE[field], operator.public_send(field)
    end
  end

  test "is configured once every required field is present" do
    assert_predicate LegalOperator.new(**COMPLETE), :configured?
    assert_empty LegalOperator.new(**COMPLETE).missing_fields
  end

  test "a blank value counts as unset, not as an empty string" do
    operator = LegalOperator.new(**COMPLETE, name: "   ")

    assert_nil operator.name
    assert_not_predicate operator, :configured?
    assert_equal [ :name ], operator.missing_fields
  end

  test "reports every missing required field, so the gap is actionable" do
    operator = LegalOperator.new

    assert_not_predicate operator, :configured?
    assert_equal LegalOperator::REQUIRED_FIELDS, operator.missing_fields
  end

  # A sole trader has no REA registration; requiring it would leave the block
  # permanently "incomplete" for a legitimate operator.
  test "the REA number is optional" do
    operator = LegalOperator.new(**COMPLETE.except(:rea_number))

    assert_nil operator.rea_number
    assert_predicate operator, :configured?
  end

  test "reads the identity out of a configuration hash" do
    operator = LegalOperator.from(COMPLETE.merge(ignored: "not a field"))

    assert_equal COMPLETE[:name], operator.name
    assert_predicate operator, :configured?
  end

  test "current reads config/legal.yml" do
    assert_kind_of LegalOperator, LegalOperator.current
  end

  # config_for re-reads and re-evaluates the file on every call, and these two
  # pages have no reason to pay for that per request.
  test "current is memoised until reset" do
    first = LegalOperator.current
    assert_same first, LegalOperator.current

    LegalOperator.reset!
    assert_not_same first, LegalOperator.current
  ensure
    LegalOperator.reset!
  end

  test "an incomplete identity is announced at boot, naming the missing fields" do
    logger = FakeLogger.new
    incomplete = LegalOperator.new(**COMPLETE.except(:phone, :vat_number))

    LegalOperator.warn_if_incomplete(incomplete, logger: logger)

    assert_equal 1, logger.warnings.size
    assert_match(/phone/, logger.warnings.first)
    assert_match(/vat_number/, logger.warnings.first)
  end

  test "a complete identity says nothing at boot" do
    logger = FakeLogger.new

    LegalOperator.warn_if_incomplete(LegalOperator.new(**COMPLETE), logger: logger)

    assert_empty logger.warnings
  end

  class FakeLogger
    attr_reader :warnings

    def initialize
      @warnings = []
    end

    def warn(message)
      @warnings << message
    end
  end

  test "env var names are derived from the field names" do
    assert_equal "LEGAL_NAME", LegalOperator.env_var(:name)
    assert_equal "LEGAL_VAT_NUMBER", LegalOperator.env_var(:vat_number)
  end

  test "is immutable" do
    assert_predicate LegalOperator.new(**COMPLETE), :frozen?
  end
end
