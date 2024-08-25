class UserWithRestrictWithError < User
  has_many :probable_family_members, class_name: 'User', foreign_key: :last_name, primary_key: :last_name, dependent: :restrict_with_error
end
