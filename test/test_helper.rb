ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
  end
end

module ActionDispatch
  class IntegrationTest
    def sign_in_as(user, password: "password123")
      post sign_in_path, params: { email: user.email, password: password }
      follow_redirect!
    end
  end
end
