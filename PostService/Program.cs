using PostalApi.Models;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls("http://localhost:5050");
// requests.http використовує назви переліку Department/Courier/ExpressCourier.
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
var app = builder.Build();

// Сховище існує лише в пам’яті цього процесу.
List<Posting> postings = new List<Posting>
{
    new Posting { Id = 1, From = "Alice", To = "Bob", Content = "Books", DeliveryType = DeliveryType.Courier, Weight = 2.5f, Width = 30, Height = 20, Depth = 10, Value = 50, Price = 10, CreatedAt = DateTime.UtcNow },
    new Posting { Id = 2, From = "Carol", To = "David", Content = "Clothes", DeliveryType = DeliveryType.Department, Weight = 1.2f, Width = 25, Height = 15, Depth = 10, Value = 100, Price = 15, CreatedAt = DateTime.UtcNow },
    new Posting { Id = 3, From = "Eve", To = "Frank", Content = "Gift", DeliveryType = DeliveryType.ExpressCourier, Weight = 0.8f, Width = 15, Height = 15, Depth = 15, Value = 75, Price = 20, CreatedAt = DateTime.UtcNow }
};

// HTTP-запити можуть виконуватися одночасно: список і лічильник захищено одним lock.
object sync = new object();
int nextId = 4;

app.MapGet("/", () => "Це API поштового клієнта.");

app.MapGet("/postings", () =>
{
    lock (sync) return Results.Ok(postings.ToArray());
});

app.MapGet("/postings/{id:int}", (int id) =>
{
    lock (sync)
    {
        var posting = postings.FirstOrDefault(p => p.Id == id);
        return posting is null ? Results.NotFound() : Results.Ok(posting);
    }
});

app.MapPost("/postings", (Posting posting) =>
{
    lock (sync)
    {
        // Ідентифікатор не залежить від поточного розміру списку або Id клієнта.
        posting.Id = nextId++;
        posting.CreatedAt = DateTime.UtcNow;
        postings.Add(posting);
        return Results.Created($"/postings/{posting.Id}", posting);
    }
});

app.MapPut("/postings/{id:int}", (int id, Posting updated) =>
{
    lock (sync)
    {
        int index = postings.FindIndex(p => p.Id == id);
        if (index < 0) return Results.NotFound();

        updated.Id = id;
        updated.CreatedAt = postings[index].CreatedAt;
        // Замінюється один запис; список та інші відправлення лишаються на місці.
        // Попередній об’єкт більше не змінюється під час серіалізації іншої відповіді.
        postings[index] = updated;
        return Results.Ok(updated);
    }
});

app.MapDelete("/postings/{id:int}", (int id) =>
{
    lock (sync)
    {
        var posting = postings.FirstOrDefault(p => p.Id == id);
        if (posting is null) return Results.NotFound();
        postings.Remove(posting);
        return Results.NoContent();
    }
});

app.Run();
