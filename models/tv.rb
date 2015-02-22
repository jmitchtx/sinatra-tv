require 'mongoid'

class TV
  include Mongoid::Document
  
  field :name
  field :current, type: Boolean, default: false
  
  scope :current, ->{ where(current: true) }
  
  validates_presence_of :name
  validates_uniqueness_of :name
  
  def self.tv
    current.one
  end
  
  def self.default name
    all.map{|tv| tv.tap{|t| t.current = false}.save}
    all.where(name: name).one.tap{|t| t.current = true}.save
  end
  
  def self.volume volume
    %x{ssh #{TV.tv.name} "osascript -e 'set Volume #{volume}'"}
  end
end