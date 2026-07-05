module Owner
  class WineLookupsController < BaseController
    # JSON-only endpoint: the sidebar query is wasted work here.
    skip_before_action :set_sidebar_restaurants

    # Second guard on the upstream daily quota (client cache is the first).
    # Declarative framework behavior — exercised manually, not unit-tested
    # (Rails.cache is a null store in test, so the limiter never trips there).
    rate_limit to: 30, within: 1.minute, only: :index,
               with: -> { render json: [], status: :too_many_requests }

    QUERY_LENGTH_RANGE = (3..100)

    def index
      query = params[:q].to_s.strip
      return render json: [] unless QUERY_LENGTH_RANGE.cover?(query.length)

      render json: WineSearcher::Client.new.search(query).map(&:to_h)
    end
  end
end
