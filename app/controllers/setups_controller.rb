# Saved army lineups (epic cyvasse-revival piece 10b). The setup panel of
# /play and of an online match posts here to save the army on the board to one
# of the player's three slots; loading one happens in the browser, from the
# slots the page was drawn with (Setup.slots_for).
#
#   POST /lineups  JSON { slot, name, lineup }  ->  { slots: [...] }
#                  422  { error, slots } when the name or army will not do
class SetupsController < ApplicationController
  def create
    attributes = { user: current_user, button_position: params[:slot].to_i, name: params[:name].to_s.strip,
                   units_position: params[:lineup].to_s }
    setup = Setup.new(attributes)
    unless setup.valid?
      return render json: { error: setup.errors.full_messages.to_sentence, slots: slots_json }, status: :unprocessable_entity
    end

    rescue_and_log(target: current_user) do
      Setup.save_slot!(current_user, slot: setup.button_position, name: setup.name, lineup: setup.units_position)
    end
    render json: { slots: slots_json }
  end

  private

  def slots_json
    Setup.slots_for(current_user).map { |slot, setup| { slot: slot, name: setup&.name.to_s, lineup: setup&.lineup } }
  end
end
