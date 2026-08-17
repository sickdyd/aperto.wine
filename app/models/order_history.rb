# A per-restaurant order history held in a signed, 24-hour cookie — there
# is no order_histories table and there will not be one. Follows the
# precedent of Cart: a plain, non-ActiveRecord object living in app/models,
# keyed by restaurant_id.to_s, every mutation assigning a new hash/array
# rather than mutating the parsed one in place.
#
# Cookie shape (mirrors Cart's session[:carts] and MenusController's
# session[:table_tokens] restaurant_id.to_s => value precedent):
#
#   cookies.signed[:order_tokens] = {
#     "42" => ["tokenB", "tokenA"],
#     "7"  => ["tokenC"]
#   }.to_json
#
# Restaurant keys are newest-written-first — hash insertion order is what
# JSON round-trips, and that order is the MAX_RESTAURANTS eviction policy
# (see #record).
#
# Signed rather than encrypted: the tokens aren't secret from the device
# that holds them — they already sit in the order confirmation URL — so
# signing, which only has to stop a forged or stuffed cookie, is the right
# and smaller tool.
class OrderHistory
  COOKIE_NAME = :order_tokens
  TTL = 24.hours
  MAX_TOKENS_PER_RESTAURANT = 15
  MAX_RESTAURANTS = 3

  def initialize(cookies:, restaurant:)
    @cookies = cookies
    @restaurant = restaurant
  end

  # No-op for an order that doesn't belong to this restaurant — a
  # defensive guard, since a caller passing an unrelated order would poison
  # the isolation guarantee #orders relies on the query for.
  def record(order)
    return unless order.restaurant_id == restaurant.id

    current = parsed_cookie
    updated_tokens = ([ order.public_token ] + restaurant_tokens(current)).uniq.first(MAX_TOKENS_PER_RESTAURANT)

    # Move this restaurant's key to the front, then keep only the first
    # MAX_RESTAURANTS keys — the least recently written restaurant is the
    # one that falls off.
    reordered = { restaurant_key => updated_tokens }.merge(current.except(restaurant_key))
    write(reordered.first(MAX_RESTAURANTS).to_h)
    reset_memos
  end

  # Array<String>, newest first. Parses the cookie defensively: anything
  # malformed — absent, tampered, not JSON, not a Hash, this restaurant's
  # value not an Array of Strings — yields [], never an exception.
  #
  # Memoized because #orders reads it three times (once to test for empty,
  # twice inside #resolve_orders) and each read re-parses and re-verifies
  # the cookie's HMAC.
  def tokens
    @tokens ||= restaurant_tokens(parsed_cookie)
  end

  # Array<Order>, newest first. One query, scoped through restaurant.orders
  # — that scoping *is* the isolation guarantee (a token planted under this
  # restaurant's key but belonging to another restaurant must not resolve).
  # The restaurant itself is already Restaurant.active by construction
  # (CustomerScoped#set_restaurant resolves it that way), so no extra
  # active check belongs here. Never rewrites the cookie: a read has no
  # side effects, even when a stored token no longer resolves.
  def orders
    @orders ||= tokens.empty? ? [] : resolve_orders
  end

  def any?
    orders.any?
  end

  private

  attr_reader :cookies, :restaurant

  def restaurant_key
    restaurant.id.to_s
  end

  # Both memos, not just @orders: #orders is derived from #tokens, so a read
  # after a write would otherwise serve the pre-write list. Cart#persist ends
  # the same way, clearing its own loaded flag for the same reason.
  def reset_memos
    @tokens = nil
    @orders = nil
  end

  # No eager loads: every caller reads only created_at, total_amount_cents,
  # status and public_token (see orders/index), or just #size / #any?. An
  # includes() here would put a second query on the menu — the hottest page
  # in the app — for every device that has ordered.
  def resolve_orders
    found = restaurant.orders.where(public_token: tokens).index_by(&:public_token)
    tokens.filter_map { |token| found[token] }
  end

  # This restaurant's token list from an already-parsed cookie hash,
  # clamped and type-checked — a hand-crafted or stale cookie could still
  # carry more entries than the write side allows, or entries of the wrong
  # shape, so this guard applies on every read, not just at parse time.
  def restaurant_tokens(parsed)
    candidate = parsed[restaurant_key]
    return [] unless candidate.is_a?(Array)
    return [] unless candidate.all? { |token| token.is_a?(String) }

    candidate.first(MAX_TOKENS_PER_RESTAURANT)
  end

  # {} for anything that isn't a well-formed signed JSON object: cookie
  # absent/blank, signature invalid (cookies.signed returns nil), not valid
  # JSON, or valid JSON that isn't a Hash.
  def parsed_cookie
    raw = cookies.signed[COOKIE_NAME]
    # is_a?(String) as well as blank?: JSON.parse raises TypeError, which the
    # rescue below does not catch, on anything that isn't a String — and a
    # jar holding a value written as a Hash would hand back exactly that.
    return {} unless raw.is_a?(String)
    return {} if raw.blank?

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def write(data)
    cookies.signed[COOKIE_NAME] = {
      value: data.to_json,
      expires: TTL.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }
  end
end
