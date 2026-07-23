require "test_helper"

class UserTest < ActiveSupport::TestCase
  def valid_attributes
    { email: "user@example.com", name: "Test User", password: "password123", password_confirmation: "password123", role: :customer }
  end

  test "creates a valid user" do
    user = User.new(valid_attributes)
    assert user.valid?
  end

  test "requires email" do
    user = User.new(valid_attributes.merge(email: ""))
    assert_not user.valid?
    assert user.errors.of_kind?(:email, :blank)
  end

  test "requires unique email" do
    User.create!(valid_attributes)
    user = User.new(valid_attributes.merge(name: "Another"))
    assert_not user.valid?
    assert user.errors.of_kind?(:email, :taken)
  end

  test "normalizes email" do
    user = User.new(valid_attributes.merge(email: "  TEST@Example.COM  "))
    user.valid?
    assert_equal "test@example.com", user.email
  end

  test "requires password minimum 8 characters" do
    user = User.new(valid_attributes.merge(password: "short", password_confirmation: "short"))
    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)
  end

  test "requires name" do
    user = User.new(valid_attributes.merge(name: ""))
    assert_not user.valid?
  end

  test "enum roles" do
    user = User.new(valid_attributes.merge(role: :owner))
    assert user.owner?

    user.role = :admin
    assert user.admin?

    user.role = :customer
    assert user.customer?
  end

  test "confirm! sets confirmed_at" do
    user = User.create!(valid_attributes)
    assert_not user.confirmed?
    user.confirm!
    assert user.confirmed?
    assert_not_nil user.confirmed_at
  end

  test "authenticates with correct password" do
    user = User.create!(valid_attributes)
    assert user.authenticate("password123")
    assert_not user.authenticate("wrong")
  end
end
