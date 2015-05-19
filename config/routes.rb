Rails.application.routes.draw do
  root to: 'scaffoldings#input_request', as: 'root'

  get '/search', to: 'scaffoldings#search', as: 'search'
  get '/index', to: 'scaffoldings#index', as: 'index'
end
