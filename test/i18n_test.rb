# frozen_string_literal: true

require "test_helper"
require "i18n/tasks"

# Static analysis of the locale files (config/i18n-tasks.yml). Production runs
# in Italian while the rest of the suite runs under :en, so without this a key
# added to en.yml but forgotten in it.yml would silently fall back to English on
# every owner page. This is the regression guard for that drift.
#
# The template's `test_files_are_normalized` check is intentionally omitted:
# `i18n-tasks normalize` rewrites the YAML and strips every comment, and both
# locale files carry load-bearing translator notes we keep.
class I18nTest < ActiveSupport::TestCase
  def setup
    @i18n = I18n::Tasks::BaseTask.new
  end

  test "no missing keys" do
    missing_keys = @i18n.missing_keys
    assert_empty missing_keys,
      "#{missing_keys.leaves.count} missing i18n keys, run `bundle exec i18n-tasks missing' to list them"
  end

  test "no unused keys" do
    unused_keys = @i18n.unused_keys
    assert_empty unused_keys,
      "#{unused_keys.leaves.count} unused i18n keys, run `bundle exec i18n-tasks unused' to list them"
  end

  test "no inconsistent interpolations" do
    inconsistent = @i18n.inconsistent_interpolations
    assert_empty inconsistent,
      "#{inconsistent.leaves.count} i18n keys have inconsistent interpolations, " \
      "run `bundle exec i18n-tasks check-consistent-interpolations' to list them"
  end
end
