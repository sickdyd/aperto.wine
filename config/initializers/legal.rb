# The operator identity on /privacy and /terms is deployment configuration
# (see LegalOperator), and the way it goes wrong is quiet: the pages still
# render, with a "to be completed" marker where the legal name should be. The
# marker is visible to whoever opens the page — which is nobody, until it is a
# regulator or an app reviewer.
#
# So say it once at boot, in the deploy log, where it is noticed on the day the
# service starts rather than months later. Skipped locally, where an unset
# identity is the normal state.
Rails.application.config.after_initialize do
  LegalOperator.warn_if_incomplete unless Rails.env.local?
end
