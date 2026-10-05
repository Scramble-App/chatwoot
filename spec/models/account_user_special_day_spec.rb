require 'rails_helper'

RSpec.describe AccountUserSpecialDay do
  let(:account_user) { create(:account_user) }

  it 'needs the hours of a working day' do
    special_day = build(:account_user_special_day, account_user: account_user, open_hour: nil, close_hour: nil)

    expect(special_day).not_to be_valid
  end

  it 'needs no hours for a day off' do
    special_day = build(:account_user_special_day, account_user: account_user, day_off: true, open_hour: nil, close_hour: nil)

    expect(special_day).to be_valid
  end
end
