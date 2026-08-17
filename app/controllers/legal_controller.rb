# The two public legal documents. Unauthenticated by design — an informativa
# behind a login is an informativa nobody has been given.
#
# The prose lives in locale-suffixed templates (privacy.it.html.erb,
# privacy.en.html.erb) rather than in en.yml/it.yml: a legal document is long
# prose whose paragraphs are not reusable strings, and threading it through the
# locale files would bury both of them and give the drift guard hundreds of
# single-use keys to police. The parity guarantee here is structural instead —
# a locale with no template raises rather than silently serving the other
# language.
class LegalController < ApplicationController
  # Both documents ship together, so one date serves both. Bump it whenever the
  # prose changes in a way a reader would care about — an undated legal document
  # is one nobody can prove was in force when an order was placed.
  LAST_UPDATED = Date.new(2026, 8, 17).freeze

  before_action :set_operator

  def privacy
  end

  def terms
  end

  private

  def set_operator
    @operator = LegalOperator.current
  end
end
