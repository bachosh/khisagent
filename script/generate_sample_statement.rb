# Generates test/fixtures/files/sample_statement.csv: a 6-month Georgian-style statement of a
# fictional applicant (salary, MCC codes, an MFO loan from month 4, growing gambling, ATM cash).
# Run: bin/rails runner script/generate_sample_statement.rb
require "csv"

rng = Random.new(42)
balance = 412.35
rows = []
add = lambda do |date, description, debit: nil, credit: nil|
  balance += credit.to_f - debit.to_f
  rows << [ date.strftime("%d.%m.%Y"), description, debit && format("%.2f", debit), credit && format("%.2f", credit), "GEL", format("%.2f", balance.round(2)) ]
end

(0...6).each do |m|
  month = Date.new(2026, 4, 1) >> m
  add.(month + 2, "ხელფასი შპს ალფა ტრეიდი (Alpha Trade LLC) ს/კ 405123456", credit: 2400 + rng.rand(0..120))
  add.(month + 3, "გადახდა ბარათით CARREFOUR TBILISI MALL MCC:5411", debit: 120 + rng.rand(0..60))
  add.(month + 4, "ATM ნაღდი ფულის გატანა TBC ATM 0453 MCC:6011", debit: 300)
  add.(month + 5, "კომუნალური გადახდა თელასი", debit: 45 + rng.rand(0..20))
  add.(month + 6, "MAGTICOM მობილური MCC:4814", debit: 25)
  add.(month + 8, "სესხის დაფარვა TBC ბანკი, ხელშეკრულება 77812", debit: 380)
  add.(month + 10, "გადახდა ბარათით NIKORA MCC:5411", debit: 60 + rng.rand(0..40))
  add.(month + 12, "WISSOL PETROLEUM MCC:5541", debit: 70)
  add.(month + 14, "CRYSTALBET.GE ONLINE MCC:7995", debit: 40 * (m + 1)) if m >= 1
  add.(month + 15, "ADJARABET MCC:7995", debit: 60 * m) if m >= 3
  add.(month + 16, "სესხის დაფარვა კრედო ბანკი", debit: 210) if m >= 3
  add.(month + 16, "სესხის ჩარიცხვა კრისტალი მფო", credit: 1500) if m == 3
  add.(month + 18, "ATM ნაღდი ფულის გატანა BOG ATM MCC:6011", debit: 200 + 50 * m)
  add.(month + 19, "ჯარიმა ვადაგადაცილებისთვის, სესხი 77812", debit: 15) if m == 5
  add.(month + 20, "WOLT GEORGIA MCC:5812", debit: 35 + rng.rand(0..30))
  add.(month + 22, "გადარიცხვა ბარათზე ნ. ბერიძე", debit: 150)
  add.(month + 25, "გადახდა ბარათით SPAR MCC:5411", debit: 40 + rng.rand(0..30))
end

path = Rails.root.join("test/fixtures/files/sample_statement.csv")
CSV.open(path, "w") do |csv|
  csv << [ "ბანკი: სს თიბისი ბანკი" ]
  csv << [ "ანგარიში: GE29TB7123456789012345", "მფლობელი: გიორგი მაისურაძე" ]
  csv << []
  csv << [ "თარიღი", "დანიშნულება", "დებეტი", "კრედიტი", "ვალუტა", "ნაშთი" ]
  rows.each { |row| csv << row }
end
puts "#{rows.size} operations → #{path} (closing balance #{balance.round(2)})"
