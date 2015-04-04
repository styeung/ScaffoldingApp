require 'httparty'
require 'json'
require 'geocoder'

class ScaffoldingsController < ApplicationController
  def index
    json_response = HTTParty.get("https://data.cityofnewyork.us/resource/ipu4-2q9a.json?permit_subtype=SF&borough=MANHATTAN&$limit=10000&$select=borough,house__,street_name,zip_code,expiration_date,job_start_date", headers: {"X-App-Token" => 'vkEMCryKaxhYrQyiXjlA3ZXqA'})
    parsed_response = JSON.load(json_response.body)
    parsed_response.select! { |permit| Time.strptime(permit['expiration_date'], '%m/%d/%Y') > Time.now && Time.strptime(permit['job_start_date'], '%m/%d/%Y') < Time.now}
    some = parsed_response[0..10].map do |permit|
      Geocoder.coordinates("#{permit['house__'].strip} #{permit['street_name'].strip}, #{permit['zip_code'].strip}")
    end

    # @response = JSON.generate(parsed_response)
    @response = JSON.generate(some)
    render :index
  end
end
