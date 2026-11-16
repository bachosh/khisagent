# Demo account for local development: bin/rails db:seed
# Then sign in as demo@khisagent.ge / password123 and upload test/fixtures/files/sample_statement.csv
if Rails.env.development?
  User.find_or_create_by!(email_address: "demo@khisagent.ge") do |user|
    user.name = "დემო რისკ-მენეჯერი"
    user.company = "Demo Credit"
    user.password = "password123"
  end
  puts "Demo user: demo@khisagent.ge / password123"
end
