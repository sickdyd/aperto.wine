import { Controller } from "@hotwired/stimulus"

// Development-only helper: pre-fills the sign-in form with seeded credentials.
export default class extends Controller {
  static targets = ["email", "password"]

  fill(event) {
    const { email, password } = event.params
    this.emailTarget.value = email
    this.passwordTarget.value = password
  }
}
