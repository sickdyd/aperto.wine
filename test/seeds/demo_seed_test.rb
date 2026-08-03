require "test_helper"

# Staging runs RAILS_ENV=production, so "not production" cannot be the guard
# that keeps demo accounts with a known password out of the real production
# database. SHOW_DEV_LOGIN is what distinguishes the two.
class DemoSeedTest < ActiveSupport::TestCase
  DEMO_SEED = Rails.root.join("db/seeds/demo.rb")

  setup do
    @original = ENV["SHOW_DEV_LOGIN"]
  end

  teardown do
    ENV["SHOW_DEV_LOGIN"] = @original
  end

  test "refuses to run in production without the staging opt-in" do
    ENV.delete("SHOW_DEV_LOGIN")

    in_production do
      error = assert_raises(RuntimeError) { load DEMO_SEED }
      assert_match(/Refusing to seed demo accounts in production/, error.message)
    end
  end

  test "runs in production when SHOW_DEV_LOGIN is set, which is what staging does" do
    ENV["SHOW_DEV_LOGIN"] = "1"

    in_production do
      assert_nothing_raised { load DEMO_SEED }
    end

    assert User.exists?(email: "owner@aperto.wine")
  end

  test "creates every account the quick-login buttons offer" do
    load DEMO_SEED

    sign_in_page = Rails.root.join("app/views/sessions/new.html.erb").read
    offered = sign_in_page.scan(/email: "([^"]+@aperto\.wine)"/).flatten

    assert_equal 3, offered.size, "expected the three quick-login accounts"
    offered.each do |email|
      assert User.exists?(email: email), "#{email} is offered as a quick login but never seeded"
    end
  end

  private

  def in_production
    original = Rails.env
    Rails.env = "production"
    yield
  ensure
    Rails.env = original
  end
end
