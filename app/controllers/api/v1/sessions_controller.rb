class Api::V1::SessionsController < ApplicationController
  # POST /api/v1/session
  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password]) && user.active?
      render json: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role
      }, status: :ok
    else
      render json: { error: "Invalid email or password" }, status: :unauthorized
    end
  end
end
