# Who is behind this service. Two separate regimes want exactly this block of
# facts published: D.Lgs. 70/2003 art. 7 (information duties of an information
# society service) on the service itself, and the Digital Services Act
# (arts. 30–31), which has Apple and Google publish the same trader details on
# the store listing.
#
# The values come from the environment (config/legal.yml), not from the repo.
# All of them are public information, so the risk is not disclosure — it is a
# fork, a staging copy, or a demo publishing the production entity's identity.
#
# Unset is a state this object *reports* rather than papers over: the pages
# render a visible pending marker for a missing field, so an unfinished block
# reads as unfinished instead of as a tidy blank line.
class LegalOperator
  FIELDS = %i[name address email phone vat_number rea_number].freeze

  # LEGAL_NAME, LEGAL_ADDRESS, … — mechanical on purpose, so config/legal.yml,
  # render.yaml and the deploy test cannot disagree about a variable's name.
  ENV_PREFIX = "LEGAL_".freeze

  # A sole trader (ditta individuale) has no REA registration, so requiring it
  # would leave a legitimate operator permanently "incomplete".
  REQUIRED_FIELDS = (FIELDS - [ :rea_number ]).freeze

  def self.env_var(field)
    "#{ENV_PREFIX}#{field.to_s.upcase}"
  end

  # Memoised for the life of the process. config_for is not memoised by Rails —
  # every call re-reads and re-evaluates the ERB in config/legal.yml — and there
  # is nothing to gain from doing that per request: Render restarts the service
  # when a dashboard variable changes, so no running process ever sees two
  # different values of LEGAL_*.
  def self.current
    @current ||= from(Rails.application.config_for(:legal))
  end

  # Tests that drive the real ENV → config_for → object path need the memo
  # cleared between states. Nothing in the app should call this.
  def self.reset!
    @current = nil
  end

  def self.from(config)
    new(**FIELDS.index_with { |field| config[field] })
  end

  # Called once at boot from config/initializers/legal.rb. Lives here rather
  # than in the initializer so the message is testable without booting a second
  # environment.
  def self.warn_if_incomplete(operator = current, logger: Rails.logger)
    return if operator.configured?

    logger.warn(
      "[legal] operator identity incomplete — missing #{operator.missing_fields.join(", ")}. " \
      "/privacy and /terms will publish a pending marker in place of each one."
    )
  end

  def initialize(**values)
    @values = FIELDS.index_with { |field| values[field].presence&.to_s }.freeze
    freeze
  end

  FIELDS.each do |field|
    define_method(field) { @values[field] }
  end

  def configured?
    missing_fields.empty?
  end

  def missing_fields
    REQUIRED_FIELDS.reject { |field| @values[field].present? }
  end
end
