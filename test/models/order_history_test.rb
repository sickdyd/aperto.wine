require "test_helper"

class OrderHistoryTest < ActiveSupport::TestCase
  # Duck-typed stand-in for #record, which only ever reads restaurant_id and
  # public_token off its argument. Lets the eviction tests (which need 16+
  # distinct tokens) run without creating a pile of real Order rows.
  FakeOrder = Struct.new(:restaurant_id, :public_token)

  setup do
    @osteria = restaurants(:osteria)
    @trattoria = restaurants(:trattoria)
    @pending_order = orders(:pending_order)
    @approved_order = orders(:approved_order)
    @guest_order = orders(:guest_order)
  end

  def history_for(restaurant, cookies: build_cookies)
    OrderHistory.new(cookies: cookies, restaurant: restaurant)
  end

  # A real signed cookie jar — not a hand-rolled fake — so the tamper test
  # below exercises real signature verification, not a stand-in for it.
  def build_cookies
    ActionDispatch::TestRequest.create(Rails.application.env_config.dup).cookie_jar
  end

  # A fresh jar built from a raw cookie value, the way a browser would send
  # it back on the next request. Unlike build_cookies + #record, this jar has
  # issued nothing of its own, so its @set_cookies reflects only what the code
  # under test writes during the call being measured.
  def jar_carrying(raw)
    env = Rails.application.env_config.dup
    env["HTTP_COOKIE"] = "#{OrderHistory::COOKIE_NAME}=#{raw}"
    ActionDispatch::TestRequest.create(env).cookie_jar
  end

  # A fresh jar pre-loaded with a signed cookie holding exactly `value` —
  # used to plant malformed or cross-restaurant payloads that #record would
  # never itself produce.
  def cookies_with_signed_value(value)
    cookies = build_cookies
    cookies.signed[OrderHistory::COOKIE_NAME] = value
    cookies
  end

  def order_stub(restaurant, token)
    FakeOrder.new(restaurant.id, token)
  end

  # --- recording ---

  test "recording an order makes it appear in #tokens and #orders" do
    cookies = build_cookies
    history = history_for(@osteria, cookies: cookies)

    history.record(@pending_order)

    assert_equal [ @pending_order.public_token ], history.tokens
    assert_equal [ @pending_order ], history.orders
  end

  test "recording multiple orders keeps tokens and orders newest first" do
    history = history_for(@osteria)

    history.record(@pending_order)
    history.record(@approved_order)
    history.record(@guest_order)

    assert_equal [ @guest_order, @approved_order, @pending_order ].map(&:public_token), history.tokens
    assert_equal [ @guest_order, @approved_order, @pending_order ], history.orders
  end

  # #tokens and #orders are both memoized, so #record has to clear them.
  # Only reachable by reading before writing on one instance, which no
  # controller does today — hence a test rather than a discovered bug.
  test "a read taken before recording does not make the next read stale" do
    history = history_for(@osteria)

    assert_equal [], history.tokens
    assert_equal [], history.orders

    history.record(@pending_order)

    assert_equal [ @pending_order.public_token ], history.tokens
    assert_equal [ @pending_order ], history.orders
  end

  test "recording the same order twice yields a single entry" do
    history = history_for(@osteria)

    history.record(@pending_order)
    history.record(@approved_order)
    history.record(@pending_order)

    assert_equal [ @pending_order.public_token, @approved_order.public_token ], history.tokens
  end

  test "record is a no-op for an order belonging to a different restaurant" do
    cookies = build_cookies
    history = history_for(@osteria, cookies: cookies)

    history.record(order_stub(@trattoria, "trattoria-token"))

    assert_equal [], history.tokens
    assert_nil cookies.signed[OrderHistory::COOKIE_NAME]
  end

  test "MAX_TOKENS_PER_RESTAURANT caps a restaurant's tokens, evicting the oldest" do
    history = history_for(@osteria)

    16.times { |i| history.record(order_stub(@osteria, "token#{i}")) }

    assert_equal OrderHistory::MAX_TOKENS_PER_RESTAURANT, history.tokens.size
    assert_equal "token15", history.tokens.first
    assert_not_includes history.tokens, "token0"
  end

  test "MAX_RESTAURANTS evicts the least recently written restaurant" do
    cookies = build_cookies
    inactive = restaurants(:inactive_restaurant)
    enoteca = restaurants(:enoteca)

    history_for(@osteria, cookies: cookies).record(order_stub(@osteria, "osteria-token"))
    history_for(@trattoria, cookies: cookies).record(order_stub(@trattoria, "trattoria-token"))
    history_for(inactive, cookies: cookies).record(order_stub(inactive, "inactive-token"))
    history_for(enoteca, cookies: cookies).record(order_stub(enoteca, "enoteca-token"))

    stored = JSON.parse(cookies.signed[OrderHistory::COOKIE_NAME])
    assert_equal OrderHistory::MAX_RESTAURANTS, stored.size
    assert_not_includes stored.keys, @osteria.id.to_s
    assert_includes stored.keys, enoteca.id.to_s
  end

  test "the written cookie carries all four of its intended attributes" do
    cookies = build_cookies
    history_for(@osteria, cookies: cookies).record(@pending_order)

    attributes = cookies.instance_variable_get(:@set_cookies)[OrderHistory::COOKIE_NAME.to_s]
    assert_in_delta OrderHistory::TTL.from_now.to_i, attributes[:expires].to_i, 5
    assert attributes[:httponly]
    assert_equal :lax, attributes[:same_site]
    # secure is gated on Rails.env.production?, so under test it must be
    # present and false — not absent. Worth pinning: the gate names one
    # environment, so adding a staging.rb later would silently serve this
    # cookie over plain HTTP.
    assert_equal false, attributes[:secure]
  end

  # The caps have well under one doubling of headroom against Rails'
  # 4096-byte CookieOverflow limit, and the overflow would raise inside
  # #record — i.e. after PlaceOrder has already committed the order, handing
  # the diner a 500 on an order that succeeded. Guard the invariant rather
  # than leave it to be rediscovered.
  test "the largest cookie the caps allow stays under the 4096-byte limit" do
    cookies = build_cookies
    all = [ @osteria, @trattoria, restaurants(:enoteca) ]
    assert_operator all.size, :>=, OrderHistory::MAX_RESTAURANTS

    all.first(OrderHistory::MAX_RESTAURANTS).each do |restaurant|
      history = history_for(restaurant, cookies: cookies)
      OrderHistory::MAX_TOKENS_PER_RESTAURANT.times do
        # A real has_secure_token value, so the measurement uses the token
        # length the app actually stores rather than a short stand-in.
        history.record(order_stub(restaurant, Order.generate_unique_secure_token))
      end
    end

    stored = JSON.parse(cookies.signed[OrderHistory::COOKIE_NAME])
    assert_equal OrderHistory::MAX_RESTAURANTS, stored.size
    stored.each_value { |tokens| assert_equal OrderHistory::MAX_TOKENS_PER_RESTAURANT, tokens.size }

    assert_operator cookies[OrderHistory::COOKIE_NAME].bytesize, :<,
      ActionDispatch::Cookies::MAX_COOKIE_SIZE
  end

  # --- cross-restaurant isolation ---

  test "a token recorded for one restaurant is invisible to a history built for another" do
    cookies = build_cookies
    history_for(@osteria, cookies: cookies).record(@pending_order)

    other = history_for(@trattoria, cookies: cookies)
    assert_equal [], other.tokens
    assert_equal [], other.orders
  end

  test "a token belonging to another restaurant, planted under this restaurant's key, resolves to nothing" do
    foreign_order = Order.create!(restaurant: @trattoria, guest_name: "Foreign Diner", total_amount_cents: 500)
    cookies = cookies_with_signed_value({ @osteria.id.to_s => [ foreign_order.public_token ] }.to_json)

    history = history_for(@osteria, cookies: cookies)

    # The token is still in the raw list...
    assert_equal [ foreign_order.public_token ], history.tokens
    # ...but the query, scoped through restaurant.orders, refuses to resolve it.
    assert_equal [], history.orders
  end

  # --- defensive reading ---

  test "an absent cookie yields no tokens" do
    assert_equal [], history_for(@osteria).tokens
  end

  test "a blank cookie yields no tokens" do
    assert_equal [], history_for(@osteria, cookies: jar_carrying("")).tokens
  end

  test "a cookie holding non-JSON content yields no tokens" do
    cookies = cookies_with_signed_value("not json")
    assert_equal [], history_for(@osteria, cookies: cookies).tokens
  end

  test "a cookie holding a JSON array instead of a hash yields no tokens" do
    cookies = cookies_with_signed_value('["an","array"]')
    assert_equal [], history_for(@osteria, cookies: cookies).tokens
  end

  test "a restaurant entry that is not an array yields no tokens" do
    cookies = cookies_with_signed_value({ @osteria.id.to_s => "not-an-array" }.to_json)
    assert_equal [], history_for(@osteria, cookies: cookies).tokens
  end

  test "a restaurant entry containing non-string elements yields no tokens" do
    cookies = cookies_with_signed_value({ @osteria.id.to_s => [ "ok", 5 ] }.to_json)
    assert_equal [], history_for(@osteria, cookies: cookies).tokens
  end

  test "a restaurant entry longer than the cap is clamped on read" do
    long_list = (1..20).map { |i| "token#{i}" }
    cookies = cookies_with_signed_value({ @osteria.id.to_s => long_list }.to_json)

    assert_equal long_list.first(OrderHistory::MAX_TOKENS_PER_RESTAURANT), history_for(@osteria, cookies: cookies).tokens
  end

  test "a tampered signed cookie yields no tokens" do
    cookies = build_cookies
    history_for(@osteria, cookies: cookies).record(@pending_order)
    raw = cookies[OrderHistory::COOKIE_NAME]
    tampered = raw.sub(/.\z/) { |char| char == "a" ? "b" : "a" }

    # The untampered value round-trips through the same jar (see the
    # no-rewrite test below), so an empty result here is signature
    # verification refusing it, not the jar failing to parse it.
    assert_equal [], history_for(@osteria, cookies: jar_carrying(tampered)).tokens
  end

  # --- reads have no side effects ---

  test "a token whose order no longer exists is skipped without rewriting the cookie" do
    written = build_cookies
    history_for(@osteria, cookies: written).record(@pending_order)
    history_for(@osteria, cookies: written).record(@approved_order)
    @pending_order.destroy!

    # The read runs against a fresh jar carrying only what a browser would
    # send back, so @set_cookies starts empty and any write during the read
    # is visible in it.
    cookies = jar_carrying(written[OrderHistory::COOKIE_NAME])
    history = history_for(@osteria, cookies: cookies)

    assert_equal [ @approved_order ], history.orders

    # Deliberately "no Set-Cookie was issued at all" rather than "the value
    # is unchanged": a rewrite with byte-identical content would still slide
    # the 24-hour expiry forward on every page view, quietly turning the
    # retention promise into an indefinite one.
    assert_empty cookies.instance_variable_get(:@set_cookies)
  end

  # --- #any? ---

  test "any? is false for a fresh device with no history" do
    assert_not history_for(@osteria).any?
  end

  test "any? is true once an order has been recorded" do
    cookies = build_cookies
    history_for(@osteria, cookies: cookies).record(@pending_order)

    assert history_for(@osteria, cookies: cookies).any?
  end
end
