# frozen_string_literal: true

module Leash
  # Authenticated Leash user.
  #
  # Mirrors the TS `LeashUser` interface — JSON fields use camelCase on the
  # wire (`id`, `email`, `name`, `picture`), and on the Ruby side `picture` is
  # optional. Two `LeashUser`s are equal when every attribute matches.
  class User
    attr_reader :id, :email, :name, :picture

    def initialize(id:, email:, name: nil, picture: nil)
      @id = id
      @email = email
      @name = name
      @picture = picture
    end

    def ==(other)
      other.is_a?(User) &&
        id == other.id &&
        email == other.email &&
        name == other.name &&
        picture == other.picture
    end

    alias eql? ==

    def hash
      [self.class, id, email, name, picture].hash
    end

    def to_h
      h = { id: id, email: email, name: name }
      h[:picture] = picture if picture
      h
    end
  end

  # Older alias — readers reaching for `Leash::LeashUser` get the same class.
  LeashUser = User
end
