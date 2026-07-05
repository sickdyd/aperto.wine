// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { Autocomplete } from "stimulus-autocomplete"

eagerLoadControllersFrom("controllers", application)
application.register("autocomplete", Autocomplete)
