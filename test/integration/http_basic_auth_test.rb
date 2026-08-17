require "test_helper"

class HttpBasicAuthTest < ActionDispatch::IntegrationTest
  # The gate reads ENV at request time, so each test sets/restores the vars.
  # Parallel test workers are separate processes, so this is process-local.
  setup do
    @original_user = ENV["HTTP_AUTH_USER"]
    @original_password = ENV["HTTP_AUTH_PASSWORD"]
  end

  teardown do
    ENV["HTTP_AUTH_USER"] = @original_user
    ENV["HTTP_AUTH_PASSWORD"] = @original_password
  end

  test "site is open when HTTP_AUTH_USER is not set" do
    ENV.delete("HTTP_AUTH_USER")
    ENV.delete("HTTP_AUTH_PASSWORD")

    get root_path

    assert_response :success
  end

  test "rejects requests without credentials when auth is configured" do
    ENV["HTTP_AUTH_USER"] = "admin"
    ENV["HTTP_AUTH_PASSWORD"] = "secret"

    get root_path

    assert_response :unauthorized
  end

  test "rejects requests with wrong credentials" do
    ENV["HTTP_AUTH_USER"] = "admin"
    ENV["HTTP_AUTH_PASSWORD"] = "secret"

    get root_path, headers: basic_auth_header("admin", "wrong")

    assert_response :unauthorized
  end

  test "allows requests with valid credentials" do
    ENV["HTTP_AUTH_USER"] = "admin"
    ENV["HTTP_AUTH_PASSWORD"] = "secret"

    get root_path, headers: basic_auth_header("admin", "secret")

    assert_response :success
  end

  test "rejects a malformed Basic header without crashing" do
    ENV["HTTP_AUTH_USER"] = "admin"
    ENV["HTTP_AUTH_PASSWORD"] = "secret"

    # Decoded payload has no colon, so Rails yields password = nil.
    get root_path, headers: { "Authorization" => "Basic #{Base64.strict_encode64('onlyuser')}" }

    assert_response :unauthorized
  end

  test "gates the public menu and owner area too" do
    ENV["HTTP_AUTH_USER"] = "admin"
    ENV["HTTP_AUTH_PASSWORD"] = "secret"

    get published_menu_path(restaurants(:osteria))
    assert_response :unauthorized

    get owner_restaurants_path
    assert_response :unauthorized
  end

  private

  def basic_auth_header(user, password)
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
  end
end
