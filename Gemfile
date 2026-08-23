source "https://rubygems.org"

# Specify your gem's dependencies in kitchen-habitat.gemspec
gemspec development_group: :test
group :test do
  gem "fakefs"
  gem "rake", ">= 11.0"
  gem "rspec", "~> 3.2"
  gem "simplecov", "~> 0.22"
end

group :docs do
  gem "yard"
end

group :debug do
  gem "pry"
end

group :cookstyle do
  gem "cookstyle"
end
