require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  # GET /sign_in
  test "GET /sign_in renders sign in form" do
    get sign_in_path
    assert_response :success
  end

  # POST /sign_in — success as customer
  test "POST /sign_in with valid credentials signs in customer and redirects to root" do
    post sign_in_path, params: { email: users(:customer).email, password: "password123" }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end

  # POST /sign_in — success as owner redirects to owner dashboard
  test "POST /sign_in with valid owner credentials redirects to owner restaurants" do
    post sign_in_path, params: { email: users(:owner).email, password: "password123" }
    assert_redirected_to owner_restaurants_path
  end

  # POST /sign_in — wrong password
  test "POST /sign_in with invalid password re-renders sign in form" do
    post sign_in_path, params: { email: users(:customer).email, password: "wrongpassword" }
    assert_response :unprocessable_entity
  end

  # POST /sign_in — unknown email
  test "POST /sign_in with unknown email re-renders sign in form" do
    post sign_in_path, params: { email: "nobody@example.com", password: "password123" }
    assert_response :unprocessable_entity
  end

  # POST /sign_in — unconfirmed user
  test "POST /sign_in with unconfirmed user redirects back to sign in with alert" do
    post sign_in_path, params: { email: users(:unconfirmed).email, password: "password123" }
    assert_redirected_to sign_in_path
  end

  # DELETE /sign_out
  test "DELETE /sign_out signs out user and redirects to root" do
    sign_in_as users(:customer)
    delete sign_out_path
    assert_redirected_to root_path
    # After sign out, accessing a protected page should redirect to sign in
    get owner_restaurants_path
    assert_redirected_to sign_in_path
  end

  test "DELETE /sign_out works even when not signed in" do
    delete sign_out_path
    assert_redirected_to root_path
  end

  # --- Flash layout (Task 5, Part E regression fix) ---

  # The flash used to be rendered both by this view and by the layout. It is
  # now the layout's alone, and it floats: the band belongs to the fixed
  # `.toast-stack`, never to the form column it is reporting on.
  test "invalid credentials render exactly one flash, floating over the form" do
    post sign_in_path, params: { email: "nobody@example.com", password: "wrongpassword" }
    assert_response :unprocessable_entity
    assert_select "[role='alert']", 1
    assert_select "div.toast-stack [role='alert']", 1
    assert_select "div.max-w-sm [role='alert']", 0
  end

  # An ERB comment ends at the FIRST `%>`, so one written inside `<%#  %>`
  # closes the comment early and spills the rest of the prose onto the page as
  # markup. The flash partials carry long explanatory comments, and every
  # existing assertion still passed while a paragraph of them rendered across
  # the masthead — the band was intact, the leak was simply elsewhere. The
  # stray terminator is the tell.
  test "the flash partials do not leak their own comments onto the page" do
    post sign_in_path, params: { email: "nobody@example.com", password: "wrongpassword" }

    assert_response :unprocessable_entity
    refute_includes response.body, "%>",
      "a stray ERB terminator reached the page — a comment in one of the " \
      "flash partials is closing early and spilling its prose into the markup"
  end
end
