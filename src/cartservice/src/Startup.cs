using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using cartservice.cartstore;
using cartservice.services;
using Microsoft.Extensions.Caching.StackExchangeRedis;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using StackExchange.Redis;

namespace cartservice
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }
        
        // This method gets called by the runtime. Use this method to add services to the container.
        // For more information on how to configure your application, visit https://go.microsoft.com/fwlink/?LinkID=398940
        public void ConfigureServices(IServiceCollection services)
        {
            string redisAddress = Configuration["REDIS_ADDR"];
            string spannerProjectId = Configuration["SPANNER_PROJECT"];
            string spannerConnectionString = Configuration["SPANNER_CONNECTION_STRING"];
            string alloyDBConnectionString = Configuration["ALLOYDB_PRIMARY_IP"];
            IConnectionMultiplexer redisConnection = null;

            if (!string.IsNullOrEmpty(redisAddress))
            {
                // Create Redis connection for instrumentation
                var redisOptions = ConfigurationOptions.Parse(redisAddress);
                redisConnection = ConnectionMultiplexer.Connect(redisOptions);
                services.AddSingleton<IConnectionMultiplexer>(redisConnection);

                services.AddStackExchangeRedisCache(options =>
                {
                    options.ConnectionMultiplexerFactory = () => Task.FromResult(redisConnection);
                });
                services.AddSingleton<ICartStore, RedisCartStore>();
            }
            else if (!string.IsNullOrEmpty(spannerProjectId) || !string.IsNullOrEmpty(spannerConnectionString))
            {
                services.AddSingleton<ICartStore, SpannerCartStore>();
            }
            else if (!string.IsNullOrEmpty(alloyDBConnectionString))
            {
                Console.WriteLine("Creating AlloyDB cart store");
                services.AddSingleton<ICartStore, AlloyDBCartStore>();
            }
            else
            {
                Console.WriteLine("Redis cache host(hostname+port) was not specified. Starting a cart service using in memory store");
                services.AddDistributedMemoryCache();
                services.AddSingleton<ICartStore, RedisCartStore>();
            }

            // OpenTelemetry configuration
            string enableTracing = Configuration["ENABLE_TRACING"];
            if (!string.IsNullOrEmpty(enableTracing) && enableTracing == "1")
            {
                string serviceName = Configuration["OTEL_SERVICE_NAME"] ?? "cartservice";
                string collectorAddr = Configuration["COLLECTOR_SERVICE_ADDR"] ?? "otel-collector:4317";

                Console.WriteLine($"OpenTelemetry Tracing enabled. Service name: {serviceName}, Collector: {collectorAddr}");

                services.AddOpenTelemetry()
                    .WithTracing(tracerProviderBuilder =>
                    {
                        var builder = tracerProviderBuilder
                            .SetResourceBuilder(
                                ResourceBuilder.CreateDefault()
                                    .AddService(serviceName: serviceName, serviceVersion: "1.0.0"))
                            .AddAspNetCoreInstrumentation()
                            .AddGrpcClientInstrumentation()
                            .AddHttpClientInstrumentation()
                            .AddSource(serviceName)
                            .AddOtlpExporter(options =>
                            {
                                options.Endpoint = new Uri($"http://{collectorAddr}");
                            });

                        // Add Redis instrumentation if Redis is configured
                        if (redisConnection != null)
                        {
                            builder.AddRedisInstrumentation(redisConnection, options =>
                            {
                                options.SetVerboseDatabaseStatements = true;
                            });
                        }
                    });
            }

            services.AddGrpc();
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }

            app.UseRouting();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapGrpcService<CartService>();
                endpoints.MapGrpcService<cartservice.services.HealthCheckService>();

                endpoints.MapGet("/", async context =>
                {
                    await context.Response.WriteAsync("Communication with gRPC endpoints must be made through a gRPC client. To learn how to create a client, visit: https://go.microsoft.com/fwlink/?linkid=2086909");
                });
            });
        }
    }
}
