require 'spec_helper'
require 'hiera/backend/vault_backend'

class Hiera
  module Backend
    describe Vault_backend do

      before do
        Hiera.stubs(:debug)
        Hiera.stubs(:warn)
        Hiera::Backend.stubs(:empty_answer).returns(nil)
      end

      describe '#initialize' do
        it "should work with empty config" do
          Config.load({:vault => {}})
          Vault_backend.new
        end

        it "should validate :default_field_parse" do
          Config.load({:vault => {:default_field_parse => 'invalid'}})
          expect { Vault_backend.new }.to raise_error /invalid value for :default_field_parse/
        end

        it "should validate :default_field_behavior" do
          Config.load({:vault => {:default_field_behavior => 'invalid'}})
          expect { Vault_backend.new }.to raise_error /invalid value for :default_field_behavior/
        end

        it "should skip backend on configuration error" do
          Vault::Client.stubs(:new).raises(Exception)
          Hiera.expects(:warn).with(regexp_matches /Skipping backend/).once

          Config.load({:vault => {}})
          Vault_backend.new
        end
      end

    end
  end
end
