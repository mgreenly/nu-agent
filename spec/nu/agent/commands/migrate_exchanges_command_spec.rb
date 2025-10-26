# frozen_string_literal: true

require "spec_helper"
require "nu/agent/commands/migrate_exchanges_command"

RSpec.describe Nu::Agent::Commands::MigrateExchangesCommand do
  let(:application) { instance_double("Nu::Agent::Application") }
  let(:command) { described_class.new(application) }

  describe "#execute" do
    it "calls run_migrate_exchanges on the application" do
      expect(application).to receive(:run_migrate_exchanges)
      command.execute("/migrate-exchanges")
    end

    it "returns :continue" do
      allow(application).to receive(:run_migrate_exchanges)
      expect(command.execute("/migrate-exchanges")).to eq(:continue)
    end
  end
end
