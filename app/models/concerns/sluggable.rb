# URL-safe identifiers for records that appear in public paths.
#
# Including models supply three things: `slug_source` (the attribute the slug
# is derived from), `slug_fallback` (used when the source parameterizes to
# nothing — a name written entirely in symbols, say), and `slug_scope` (the
# relation the slug must be unique within).
#
# Generation only fills a *blank* slug, so an explicitly supplied one always
# wins. Models that want the slug to track their source attribute clear it
# themselves before validation — see WineList.
module Sluggable
  extend ActiveSupport::Concern

  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  MAX_LENGTH = 100

  included do
    before_validation :normalize_slug
    before_validation :assign_slug

    validates :slug,
              presence: true,
              length: { maximum: MAX_LENGTH },
              format: { with: SLUG_FORMAT, allow_blank: true },
              exclusion: { in: ->(record) { record.reserved_slugs }, allow_blank: true }
    validate :slug_must_be_available
  end

  # Slugs that would be shadowed by a route declared above the public menu
  # routes, and so could never resolve. None by default.
  def reserved_slugs
    [].freeze
  end

  private

  # Applied to owner-supplied slugs too, so "  My Own URL  " and "my-own-url"
  # cannot both exist.
  def normalize_slug
    self.slug = slug.to_s.parameterize.presence
  end

  def assign_slug
    return if slug.present?

    self.slug = generate_slug
  end

  def generate_slug
    base = slug_source.to_s.parameterize.presence || slug_fallback
    candidate = clamp(base, MAX_LENGTH)
    suffix = 1

    while slug_unavailable?(candidate)
      suffix += 1
      tail = "-#{suffix}"
      # Trim the base far enough that the suffix fits, rather than appending
      # past MAX_LENGTH and tripping the length validation on a long name.
      candidate = "#{clamp(base, MAX_LENGTH - tail.length)}#{tail}"
    end

    candidate
  end

  # Truncating mid-word can leave a trailing hyphen, which SLUG_FORMAT
  # rejects — and "foo-" + "-2" would produce a double hyphen it also
  # rejects. Strip them so a long name still yields a valid slug.
  def clamp(base, length)
    base.first(length).sub(/-+\z/, "")
  end

  def slug_unavailable?(candidate)
    reserved_slugs.include?(candidate) || slug_taken?(candidate)
  end

  def slug_taken?(candidate)
    scope = slug_scope
    return false if scope.nil?

    scope = scope.where.not(id: id) if persisted?
    scope.exists?(slug: candidate)
  end

  # The DB carries a unique index for this; the validation exists so the owner
  # gets a field-level message instead of a 500.
  def slug_must_be_available
    return if slug.blank?

    errors.add(:slug, :taken) if slug_taken?(slug)
  end
end
