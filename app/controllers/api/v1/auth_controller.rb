module Api
  module V1
    class AuthController < BaseController
      # POST /api/v1/auth/login
      def login
        user = User.find_by(email: params[:email]&.downcase)

        if user&.authenticate(params[:password]) && user.active?
          token = JsonWebToken.encode(user_id: user.id)
          
          render json: {
            token: token,
            user: {
              id: user.id,
              email: user.email,
              name: user.name,
              role: user.role
            }
          }, status: :ok
        else
          render json: { error: 'Invalid email or password' }, status: :unauthorized
        end
      end

      # GET /api/v1/auth/me
      def me
        render json: {
          user: {
            id: @current_user.id,
            email: @current_user.email,
            name: @current_user.name,
            role: @current_user.role
          }
        }
      end
    end
  end
end
