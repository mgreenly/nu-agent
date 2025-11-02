# frozen_string_literal: true

RSpec.describe Nu::Agent do
  describe "orphaned code cleanup" do
    it "does not have .bak files in lib/ directory" do
      bak_files = Dir.glob("lib/**/*.bak")
      expect(bak_files).to be_empty, "Found backup files that should be removed: #{bak_files.join(', ')}"
    end

    it "does not have .orig files in lib/ directory" do
      orig_files = Dir.glob("lib/**/*.orig")
      expect(orig_files).to be_empty, "Found .orig files that should be removed: #{orig_files.join(', ')}"
    end

    it "does not have editor backup files in lib/ directory" do
      backup_files = Dir.glob("lib/**/*~")
      expect(backup_files).to be_empty, "Found editor backup files that should be removed: #{backup_files.join(', ')}"
    end
  end
end
