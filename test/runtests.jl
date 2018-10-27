using Dates
using JSON
using Test

using Discord
using Discord:
    snowflake,
    Snowflake,
    snowflake2datetime,
    worker_id,
    process_id,
    increment,
    datetime,
    parse_endpoint,
    @boilerplate,
    @dict,
    @lower,
    @merge

# A test case which covers most possible field types.
Discord.eval(:(
struct Foo
    a::String
    b::DateTime
    c::Snowflake
    d::Vector{String}
    e::Union{Int, Nothing}
    f::Union{Int, Missing}
    g::Union{Vector{String}, Nothing, Missing}
    h::Union{Foo, Missing}
end
))
Discord.eval(:(
@boilerplate Foo :dict :docs :lower :merge
))
using Discord: Foo

# A module with event handlers.
module Handlers

export a, b

using Discord

a(::Client, ::AbstractEvent) = nothing
a(::Client, ::TypingStart) = nothing
b(::Client, ::WebhookUpdate) = nothing
c(::Client, ::WebhookUpdate) = nothing

end

@testset "Discord.jl" begin
    @testset "Client token" begin
        c = Client("token")
        @test c.token == "Bot token"
        c = Client("Bot token")
        @test c.token == "Bot token"
    end

    @testset "Snowflake" begin
        s = snowflake(string(typemax(UInt64)))
        @test isa(s, UInt64)
        @test s == typemax(UInt64)

        s = Snowflake(0x06ecefa78e42000c)
        @test snowflake2datetime(s) == DateTime(2018, 10, 9, 1, 55, 31, 1)
        @test worker_id(s) == 0x01
        @test process_id(s) == 0x00
        @test increment(s) == 0x0c
    end

    @testset "DateTime parsing" begin
        d = datetime("2018-10-08T05:20:22.782643+00:00")
        @test d == DateTime(2018, 10, 8, 5, 20, 22, 782)

        d = datetime("2018-10-08T05:20:22.782Z")
        @test d == DateTime(2018, 10, 8, 5, 20, 22, 782)
    end

    @testset "Boilerplate macros" begin
        d = Dict(
            "a" => "foo",
            "b" => "2018-10-08T05:20:22.782Z",
            "c" => "1234567890",
            "d" => ["a", "b", "c"],
            "e" => 1,
            "f" => 2,
            "g" => ["a", "b", "c"],
        )
        d["h"] = copy(d)

        f = Foo(d)
        @test f.a == "foo"
        @test f.b == DateTime(2018, 10, 8, 5, 20, 22, 782)
        @test f.c == 1234567890
        @test f.d == ["a", "b", "c"]
        @test f.e == 1
        @test f.f == 2
        @test f.g == ["a", "b", "c"]
        @test f.h isa Foo && f.h.a == "foo"

        d["e"] = nothing
        delete!(d, "f")
        delete!(d, "g")

        f = Foo(d)
        @test f.e === nothing
        @test ismissing(f.f)
        @test ismissing(f.g)

        d["g"] = nothing

        f = Foo(d)
        @test f.g === nothing

        @test occursin("a :: String", string(@doc Foo))

        d["b"] = d["h"]["b"] = round(Int, datetime2unix(f.b))
        d["c"] = d["h"]["c"] = snowflake(f.c)
        @test JSON.lower(f) == Dict(
            "a" => "foo",
            "b" => d["b"],
            "c" => d["c"],
            "d" => ["a", "b", "c"],
            "e" => nothing,
            "g" => nothing,
            "h" => d["h"],
        )

        f2 = Foo("bar", f.b, f.c, f.d, f.e, f.f, f.g, missing)
        f3 = merge(f, f2)
        @test f3.a == f2.a
        @test f3.h == f.h
    end

    @testset "parse_endpoint" begin
        # The variable paramter doesn't matter.
        @test parse_endpoint("/users/1", :GET) == "/users"
        # Unless it's one of these three.
        @test parse_endpoint("/channels/1", :GET) == "/channels/1"
        @test parse_endpoint("/guilds/1", :GET) == "/guilds/1"
        @test parse_endpoint("/webhooks/1", :GET) == "/webhooks/1"

        # Without a numeric parameter at the end, we get the whole endpoint.
        @test parse_endpoint("/users/@me/channels", :GET) == "/users/@me/channels"

        # Special case: Deleting messages.
        @test ==(
            parse_endpoint("/channels/1/messages/1", :DELETE),
            "/channels/1/messages DELETE",
        )
        @test parse_endpoint("/channels/1/messages/1", :GET) == "/channels/1/messages"
    end

    @testset "Event handler manipulation" begin
        f(c, e) = nothing
        g(c, e) = nothing
        c = Client("token")

        # Deleting handlers without a tag clears all handlers for that type.
        delete_handler!(c, MessageCreate)
        @test !haskey(c.handlers, MessageCreate)

        # Adding handlers without a tag means we can have duplicates.
        add_handler!(c, MessageCreate, f)
        add_handler!(c, MessageCreate, f)
        @test length(get(c.handlers, MessageCreate, [])) == 2
        delete_handler!(c, MessageCreate)

        # Using tags prevents duplicates.
        add_handler!(c, MessageCreate, f; tag=:f)
        add_handler!(c, MessageCreate, f; tag=:f)
        @test length(get(c.handlers, MessageCreate, [])) == 1

        # With tags, we can delete specific handlers.
        add_handler!(c, MessageCreate, g; tag=:g)
        @test length(get(c.handlers, MessageCreate, [])) == 2
        delete_handler!(c, MessageCreate, :g)
        @test length(get(c.handlers, MessageCreate, [])) == 1
        @test first(collect(c.handlers[MessageCreate])).f == f

        # We can also add handlers from a module.
        add_handler!(c, Handlers)
        @test length(get(c.handlers, AbstractEvent, [])) == 1
        @test length(get(c.handlers, TypingStart, [])) == 1
        # Only exported functions are considered.
        @test length(get(c.handlers, WebhookUpdate, [])) == 1
        @test first(collect(c.handlers[WebhookUpdate])).f == Handlers.b
    end

    @testset "Bot commands" begin
        f(c, e) = nothing
        c = Client("token")

        # Adding commands adds to the MessageCreate handlers.
        delete_handler!(c, MessageCreate)
        h(c, m) = nothing
        add_command!(c, "!test", h)
        @test length(get(c.handlers, MessageCreate, [])) == 1
        # But the handler function is modified.
        @test first(collect(c.handlers[MessageCreate])).f != f
    end
end
