module FormErrorsHelper
  # Inline, per-field error display.
  #
  # An error message is only useful to a screen reader if it is *associated*
  # with its input rather than merely sitting next to it, so the messages get
  # ids derived from the form builder (`field_id` gives the same prefix Rails
  # uses for the input itself, which keeps them unique even for fields rendered
  # in a loop) and the input points at them through `aria-describedby`.
  #
  # Usage:
  #
  #   <%= f.text_field :name, class: "input", **field_error_attributes(f, :name) %>
  #   <%= field_errors f, :name %>

  # Ids of the error paragraphs `field_errors` will render for this attribute.
  # Empty when the attribute is valid.
  def field_error_ids(form, attribute)
    form.object.errors[attribute].each_index.map { |index| form.field_id(attribute, :error, index) }
  end

  # Input attributes wiring an attribute to its error messages. `describedby`
  # takes the ids of any non-error descriptions (a hint, say) that should be
  # announced alongside them.
  def field_error_attributes(form, attribute, describedby: nil)
    error_ids = field_error_ids(form, attribute)
    described_by = (Array(describedby) + error_ids).compact_blank

    attributes = {}
    attributes["aria-invalid"] = "true" if error_ids.any?
    attributes["aria-describedby"] = described_by.join(" ") if described_by.any?
    attributes
  end

  # The error messages themselves, one paragraph per message, carrying the ids
  # `field_error_attributes` points at.
  def field_errors(form, attribute)
    messages = form.object.errors[attribute]
    return if messages.empty?

    safe_join(messages.each_with_index.map do |message, index|
      tag.p(message, class: "field-error", id: form.field_id(attribute, :error, index))
    end)
  end
end
