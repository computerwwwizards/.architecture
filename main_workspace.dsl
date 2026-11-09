workspace "Central Architecture Catalog" "Central repository for FINOS CALM and system models." {

    model {
        !include c4-catalogs/static_delivery_pipeline/system_model.dsl
    }

    views {
        !include c4-catalogs/static_delivery_pipeline/system_views.dsl

        styles {
            element "Element" {
                color "#ffffff"
            }
            element "Container" {
                background "#2563eb"
                shape RoundedBox
            }
            element "Database" {
                background "#475569"
                shape Cylinder
            }
            element "Gate" {
                background "#eab308"
                shape Hexagon
            }
            element "Storage" {
                background "#059669"
                shape Folder
            }
            element "External System" {
                background "#0f766e"
            }
            element "Person" {
                background "#0891b2"
                shape Person
            }
        }
    }
}
