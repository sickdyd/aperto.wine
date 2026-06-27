# Default accounts for development
return unless Rails.env.development?

puts "Seeding development data..."

# Admin
admin = User.find_or_create_by!(email: "admin@aperto.wine") do |u|
  u.name = "Admin"
  u.role = :admin
  u.password = "password"
  u.password_confirmation = "password"
  u.confirmed_at = Time.current
end
puts "  Admin: #{admin.email} / password"

# Owner
owner = User.find_or_create_by!(email: "owner@aperto.wine") do |u|
  u.name = "Marco Rossi"
  u.role = :owner
  u.password = "password"
  u.password_confirmation = "password"
  u.confirmed_at = Time.current
end
puts "  Owner: #{owner.email} / password"

# Sample restaurant
restaurant = owner.restaurants.find_or_create_by!(name: "Osteria del Borgo") do |r|
  r.address = "Via Roma 42, Milano"
  r.description = "Traditional Italian cuisine with a modern twist"
  r.latitude = 45.4642
  r.longitude = 9.1900
end
puts "  Restaurant: #{restaurant.name}"

# Sample wines
wines_data = [
  { name: "Barolo Riserva", producer: "Giacomo Conterno", grape_variety: "Nebbiolo", vintage_year: 2018, color: :red, region: "Piemonte", bottle_size_ml: 750, price_bottle_cents: 12_000, price_75ml_cents: 1500, price_100ml_cents: 1800, price_125ml_cents: 2200, available_glasses: 10, position: 1 },
  { name: "Brunello di Montalcino", producer: "Biondi-Santi", grape_variety: "Sangiovese", vintage_year: 2017, color: :red, region: "Toscana", bottle_size_ml: 750, price_bottle_cents: 9500, price_100ml_cents: 1400, price_125ml_cents: 1700, available_glasses: 7, position: 2 },
  { name: "Gavi di Gavi", producer: "La Scolca", grape_variety: "Cortese", vintage_year: 2022, color: :white, region: "Piemonte", bottle_size_ml: 750, price_bottle_cents: 4500, price_75ml_cents: 700, price_100ml_cents: 900, price_125ml_cents: 1100, available_glasses: 10, position: 1 },
  { name: "Franciacorta Brut", producer: "Ca' del Bosco", grape_variety: "Chardonnay", vintage_year: 2019, color: :sparkling, region: "Lombardia", bottle_size_ml: 750, price_bottle_cents: 6000, price_100ml_cents: 1000, price_125ml_cents: 1200, available_glasses: 6, position: 1 },
  { name: "Passito di Pantelleria", producer: "Ferrandes", grape_variety: "Zibibbo", vintage_year: 2020, color: :dessert, region: "Sicilia", bottle_size_ml: 500, price_75ml_cents: 900, price_100ml_cents: 1100, available_glasses: 6, position: 1 }
]

wines_data.each do |data|
  restaurant.wines.find_or_create_by!(name: data[:name]) do |w|
    w.assign_attributes(data.except(:name))
  end
end
puts "  Wines: #{restaurant.wines.count}"

# Customer
customer = User.find_or_create_by!(email: "customer@aperto.wine") do |u|
  u.name = "Giulia Bianchi"
  u.role = :customer
  u.password = "password"
  u.password_confirmation = "password"
  u.confirmed_at = Time.current
end
puts "  Customer: #{customer.email} / password"

puts "Done!"
