require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "GET / renders successfully" do
    get root_path
    assert_response :success
  end

  test "GET / renders successfully when signed in as customer" do
    sign_in_as users(:customer)
    get root_path
    assert_response :success
  end

  test "GET / renders successfully when signed in as owner" do
    sign_in_as users(:owner)
    get root_path
    assert_response :success
  end
end
