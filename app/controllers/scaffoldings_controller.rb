require 'httparty'
require 'json'
require 'geocoder'
require 'redis'

class ScaffoldingsController < ApplicationController
  def index
    current_scaffolding_data = get_current_open_nyc_data

    redis = Redis.new

    some = current_scaffolding_data[0..200].map do |permit|
      job_coordinates = get_job_coordinates(redis, permit)
      [job_coordinates['latitude'], job_coordinates['longitude']]
    end

    @response = JSON.generate(some)
    render :index
  end

  private

  def get_job_coordinates(redis, permit)
    job_number = permit['job__']
    job_coordinates = get_cached_job_coordinates(redis, job_number)

    if job_coordinates.nil?
      cache_job_coordinates(redis, permit)
      job_coordinates = get_cached_job_coordinates(redis, job_number)
    end

    job_coordinates
  end

  def get_cached_job_coordinates(redis, job_number)
    permit_json = redis.hget('job_coordinates', job_number)
    JSON.load(permit_json)
  end

  def cache_job_coordinates(redis, permit)
    job_number = permit['job__']
    coordinates = Geocoder.coordinates("#{permit['house__'].strip} #{permit['street_name'].strip}, #{permit['zip_code'].strip}")

    job = {
      job_number: job_number,
      latitude: coordinates[0],
      longitude: coordinates[1]
    }

    redis.hset("job_coordinates", job_number, job.to_json)
  end

  def get_current_open_nyc_data
    json_response = HTTParty.get("https://data.cityofnewyork.us/resource/ipu4-2q9a.json?permit_subtype=SF&borough=MANHATTAN&$limit=10000&$select=job__,borough,house__,street_name,zip_code,expiration_date,job_start_date", headers: {"X-App-Token" => 'vkEMCryKaxhYrQyiXjlA3ZXqA'})
    parsed_response = JSON.load(json_response.body)
    parsed_response.select! { |permit| Time.strptime(permit['expiration_date'], '%m/%d/%Y') > Time.now && Time.strptime(permit['job_start_date'], '%m/%d/%Y') < Time.now}
  end
end
