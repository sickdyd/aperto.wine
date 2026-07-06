module Owner
  class AddressSuggestionsController < BaseController
    # The response is a bare <li> fragment — no layout, no sidebar query.
    skip_before_action :set_sidebar_restaurants

    # Every keystroke can fan out to Photon (a shared free service); cap
    # bursts per user beyond what the client-side debounce already does.
    rate_limit to: 10, within: 3.seconds, by: -> { current_user.id }, with: -> { head :too_many_requests }

    def index
      @suggestions = Geocoding.suggestions(params[:q])
      render layout: false
    end
  end
end
