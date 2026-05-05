require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  # GET /sign_up
  test "GET /sign_up renders registration form" do
    get sign_up_path
    assert_response :success
  end

  test "GET /sign_up with tab=owner renders owner tab" do
    get sign_up_path, params: { tab: "owner" }
    assert_response :success
  end

  # POST /sign_up — register as customer
  test "POST /sign_up with valid customer params creates user and redirects to root" do
    assert_difference "User.count", 1 do
      post sign_up_path, params: {
        user: {
          name: "New Customer",
          email: "newcustomer@example.com",
          password: "password123",
          password_confirmation: "password123",
          role: "customer"
        }
      }
    end
    assert_redirected_to root_path
    assert_equal "customer", User.find_by(email: "newcustomer@example.com").role
  end

  # POST /sign_up — register as owner
  test "POST /sign_up with valid owner params creates user and redirects to owner restaurants" do
    assert_difference "User.count", 1 do
      post sign_up_path, params: {
        user: {
          name: "New Owner",
          email: "newowner@example.com",
          password: "password123",
          password_confirmation: "password123",
          role: "owner"
        }
      }
    end
    assert_redirected_to owner_restaurants_path
    assert_equal "owner", User.find_by(email: "newowner@example.com").role
  end

  # POST /sign_up — role restriction: cannot register as admin
  test "POST /sign_up attempting admin role silently creates customer instead" do
    assert_difference "User.count", 1 do
      post sign_up_path, params: {
        user: {
          name: "Sneaky Admin",
          email: "sneaky@example.com",
          password: "password123",
          password_confirmation: "password123",
          role: "admin"
        }
      }
    end
    created_user = User.find_by(email: "sneaky@example.com")
    assert_not_nil created_user
    assert_equal "customer", created_user.role
  end

  # POST /sign_up — validation errors: missing name
  test "POST /sign_up with missing name re-renders form with error" do
    assert_no_difference "User.count" do
      post sign_up_path, params: {
        user: {
          name: "",
          email: "noname@example.com",
          password: "password123",
          password_confirmation: "password123",
          role: "customer"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # POST /sign_up — validation errors: invalid email
  test "POST /sign_up with invalid email re-renders form with error" do
    assert_no_difference "User.count" do
      post sign_up_path, params: {
        user: {
          name: "Bad Email",
          email: "not-an-email",
          password: "password123",
          password_confirmation: "password123",
          role: "customer"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # POST /sign_up — validation errors: duplicate email
  test "POST /sign_up with existing email re-renders form with error" do
    assert_no_difference "User.count" do
      post sign_up_path, params: {
        user: {
          name: "Duplicate",
          email: users(:customer).email,
          password: "password123",
          password_confirmation: "password123",
          role: "customer"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # POST /sign_up — validation errors: password too short
  test "POST /sign_up with short password re-renders form with error" do
    assert_no_difference "User.count" do
      post sign_up_path, params: {
        user: {
          name: "Short Pass",
          email: "shortpass@example.com",
          password: "abc",
          password_confirmation: "abc",
          role: "customer"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # POST /sign_up — validation errors: password confirmation mismatch
  test "POST /sign_up with mismatched password confirmation re-renders form with error" do
    assert_no_difference "User.count" do
      post sign_up_path, params: {
        user: {
          name: "Mismatch",
          email: "mismatch@example.com",
          password: "password123",
          password_confirmation: "different123",
          role: "customer"
        }
      }
    end
    assert_response :unprocessable_entity
  end
end
