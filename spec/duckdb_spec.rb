# frozen_string_literal: true

require 'duckdb'

RSpec.describe 'DuckDB' do
  it 'can create a database and execute queries' do
    # Create an in-memory database
    db = DuckDB::Database.open

    # Create a connection
    conn = db.connect

    # Create a simple table
    conn.query('CREATE TABLE test (id INTEGER, name VARCHAR)')

    # Insert some data
    conn.query("INSERT INTO test VALUES (1, 'Alice'), (2, 'Bob')")

    # Query the data
    result = conn.query('SELECT * FROM test ORDER BY id')

    # Verify the results
    rows = result.to_a
    expect(rows.length).to eq(2)
    expect(rows[0][0]).to eq(1)
    expect(rows[0][1]).to eq('Alice')
    expect(rows[1][0]).to eq(2)
    expect(rows[1][1]).to eq('Bob')

    # Clean up
    conn.disconnect
  end

  it 'can use DuckDB version info' do
    db = DuckDB::Database.open
    conn = db.connect

    result = conn.query('SELECT version()')
    version = result.to_a[0][0]

    expect(version).to be_a(String)
    expect(version).not_to be_empty

    puts "DuckDB version: #{version}"

    conn.disconnect
  end
end
