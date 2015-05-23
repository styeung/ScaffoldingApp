require 'httparty'
require 'json'
require 'geocoder'
require 'redis'

class ScaffoldingsController < ApplicationController
  def input_request
    render :input_request
  end

  def search
    origin = Geocoder.coordinates(params[:origin])
    destination = Geocoder.coordinates(params[:destination])
    request_url = "https://maps.googleapis.com/maps/api/directions/json?"\
                  "origin=#{origin.join(',')}&destination=#{destination.join(',')}&"\
                  "key=#{ENV['SCAFFOLDING_APP_GOOGLE_API_KEY']}"

    @response = JSON.generate(HTTParty.get(request_url))
    total_distance = distance_between_two_points(origin, destination)

    current_scaffolding_data = get_current_open_nyc_data

    redis = Redis.new

    relevant_job_coordinates = current_scaffolding_data.select do |permit|
      job_coordinates = get_job_coordinates(redis, permit)
      next if job_coordinates.nil?
      job_coordinates_lat_lng = [job_coordinates['latitude'], job_coordinates['longitude']]

      (distance_between_two_points(job_coordinates_lat_lng, origin) < total_distance/2 && \
        distance_between_two_points(job_coordinates_lat_lng, destination) < total_distance) || \
        (distance_between_two_points(job_coordinates_lat_lng, destination) < total_distance/2 && \
        distance_between_two_points(job_coordinates_lat_lng, origin) < total_distance)
    end.map { |permit| get_job_coordinates(redis, permit) }

    @job_coordinates = JSON.generate(relevant_job_coordinates)

    render :search
  end

  def index
    current_scaffolding_data = get_current_open_nyc_data

    redis = Redis.new

    all_job_coordinates = current_scaffolding_data.map do |permit|
      get_job_coordinates(redis, permit)
    end

    @response = JSON.generate(all_job_coordinates)
    render :index
  end

  private

  def distance_between_two_points(origin, destination)
    Math.sqrt((destination[1] - origin[1])**2 + (destination[0] - origin[0])**2)
  end

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
    Geocoder.configure(
      cache: Redis.new,
      use_https: true,
      google: {
        api_key: ENV['SCAFFOLDING_APP_GOOGLE_API_KEY'],
      }
    )

    address = "#{permit['house__'].strip} #{permit['street_name'].strip}"
    coordinates = Geocoder.coordinates("#{address}, #{permit['zip_code'].strip}")

    unless coordinates.nil?

      job = {
        job_number: job_number,
        latitude: coordinates[0],
        longitude: coordinates[1],
        address: address
      }

      redis.hset("job_coordinates", job_number, job.to_json)
    end
  end

  def get_current_open_nyc_data
    json_response = HTTParty.get("https://data.cityofnewyork.us/resource/ipu4-2q9a.json?permit_subtype=SH&borough=MANHATTAN&$limit=10000&$select=job__,borough,house__,street_name,zip_code,expiration_date,job_start_date", headers: {"X-App-Token" => 'vkEMCryKaxhYrQyiXjlA3ZXqA'})
    parsed_response = JSON.load(json_response.body)
    parsed_response.select! { |permit| Time.strptime(permit['expiration_date'], '%m/%d/%Y') > Time.now && Time.strptime(permit['job_start_date'], '%m/%d/%Y') < Time.now}
  end
end
