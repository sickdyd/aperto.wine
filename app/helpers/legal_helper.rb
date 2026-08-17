module LegalHelper
  # A missing identity field must not collapse to an empty line — a block with
  # three of six rows filled reads as finished when it is not. Render the gap.
  def legal_operator_value(field)
    value = @operator.public_send(field)
    return value if value.present?

    tag.span t("legal.identity.pending"), class: "legal-pending"
  end
end
