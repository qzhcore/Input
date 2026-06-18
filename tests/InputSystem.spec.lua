--!strict

return function()
	describe("InputSystem package", function()
		it("loads the package root", function()
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local InputSystem = require(ReplicatedStorage:WaitForChild("InputSystem"))

			expect(InputSystem).to.be.ok()
			expect(InputSystem.Priority.Gameplay).to.equal(100)
		end)
	end)
end
