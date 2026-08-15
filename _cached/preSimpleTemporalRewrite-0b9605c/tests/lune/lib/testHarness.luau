--!strict

export type TestCallback = () -> ()
export type TestCase = {
	name: string,
	run: TestCallback,
}

local TestHarness = {}
local tests: { TestCase } = {}

function TestHarness.test(name: string, callback: TestCallback)
	table.insert(tests, {
		name = name,
		run = callback,
	})
end

function TestHarness.assertTrue(value: boolean, message: string?)
	assert(value, message or "expected true")
end

function TestHarness.assertFalse(value: boolean, message: string?)
	assert(not value, message or "expected false")
end

function TestHarness.assertEqual<T>(actual: T, expected: T, message: string?)
	assert(actual == expected, message or `expected {tostring(expected)}, got {tostring(actual)}`)
end

function TestHarness.assertNear(actual: number, expected: number, epsilon: number?)
	local tolerance = epsilon or 1e-9
	assert(math.abs(actual - expected) <= tolerance, `expected {expected}, got {actual}`)
end

function TestHarness.assertArrayEqual<T>(actual: { T }, expected: { T })
	TestHarness.assertEqual(#actual, #expected, "array lengths differ")
	for index, expectedValue in expected do
		TestHarness.assertEqual(actual[index], expectedValue, `arrays differ at index {index}`)
	end
end

function TestHarness.assertThrows(callback: TestCallback, pattern: string?)
	local ok, result = pcall(function(): unknown
		callback()
		return nil
	end)
	assert(not ok, "expected callback to throw")
	if pattern ~= nil then
		assert(
			string.find(tostring(result), pattern, 1, true) ~= nil,
			`expected error containing '{pattern}', got '{tostring(result)}'`
		)
	end
end

function TestHarness.run()
	local passed = 0
	local failed = 0

	for _, testCase in tests do
		local ok, result = pcall(function(): unknown
			testCase.run()
			return nil
		end)
		if ok then
			passed += 1
			print(`PASS: {testCase.name}`)
		else
			failed += 1
			print(`FAIL: {testCase.name}`)
			print(result)
		end
	end

	if failed > 0 then
		error(`Pulse specs failed: {failed} failed`, 0)
	end
	print(`Pulse specs: {passed} passed, {failed} failed`)
end

return TestHarness
