require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ApertoWine
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # rails_icons resolves SVGs straight off the filesystem (Icons::Icon::FilePath)
    # and never through the asset pipeline, so leaving app/assets/svg on the
    # Propshaft load path only makes precompile digest ~9k files (35 MB) into
    # public/assets that nothing ever requests.
    config.assets.excluded_paths += [ Rails.root.join("app/assets/svg") ]

    config.i18n.default_locale = :it
    config.i18n.available_locales = %i[en it]
    config.i18n.fallbacks = true
  end
end
