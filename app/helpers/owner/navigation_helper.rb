module Owner
  module NavigationHelper
    # True when the current request belongs to one of the given controllers
    # (and, if given, one of the actions) — used to highlight sidebar items.
    def owner_nav_active?(controllers, actions: nil)
      return false unless Array(controllers).include?(controller_name)

      actions.nil? || Array(actions).include?(action_name)
    end

    # Class + aria-current attributes for a sidebar link.
    def owner_nav_link_attrs(active)
      { class: active ? "menu-active" : nil, "aria-current": active ? "page" : nil }
    end
  end
end
