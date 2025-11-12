using OxyPlot.Series;
using OxyPlot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace CordicTest
{
    public static class PlotHelper
    {
        public static PlotModel CreatePlotModel()
        {
            var model = new PlotModel { Title = "CORDIC Sin, Cos, Tan Functions" };

            var sinSeries = new LineSeries { Title = "Sin", MarkerType = MarkerType.Circle };
            var cosSeries = new LineSeries { Title = "Cos", MarkerType = MarkerType.Triangle };
            var cosMathSeries = new LineSeries { Title = "CosMath", MarkerType = MarkerType.Triangle };
            var tanSeries = new LineSeries { Title = "Tan", MarkerType = MarkerType.Square };
            var lnSeries = new LineSeries { Title = "ln", MarkerType = MarkerType.Cross };
            var lnMathSeries = new LineSeries { Title = "lnMath", MarkerType = MarkerType.Cross };

            var sqrtSeries = new LineSeries { Title = "sqrt", MarkerType = MarkerType.Star };
            var sqrtMathSeries = new LineSeries { Title = "sqrtMath", MarkerType = MarkerType.Star };

            // Assuming we want to plot from -2π to 2π
            for (double angle = -2 * Math.PI; angle <= 2 * Math.PI; angle += 0.01)
            {
                CordicCalculator.CalculateSinCos(angle, out double sin, out double cos);
                double tan = CordicCalculator.CalculateTan(angle);

                double ln2 = CordicCalculator.CalculateLn(angle);

                sinSeries.Points.Add(new DataPoint(angle, sin));
                cosSeries.Points.Add(new DataPoint(angle, cos));
                //cosSeries.Points.Add(new DataPoint(angle, cos));

                cosMathSeries.Points.Add(new DataPoint(angle, Math.Cos(angle)));

                tanSeries.Points.Add(new DataPoint(angle, tan));
                lnSeries.Points.Add(new DataPoint(angle, ln2));


                //sqrtSeries.Points.Add(new DataPoint(angle, CordicCalculator.SqrtGoldschmidt(angle) - Math.Sqrt(angle)));
                sqrtSeries.Points.Add(new DataPoint(angle, CordicCalculator.SqrtNewtonRaphson(angle)));

                sqrtMathSeries.Points.Add(new DataPoint(angle, Math.Sqrt(angle)));

                //lnMathSeries.Points.Add(new DataPoint(angle, Math.Log(angle)));

            }

            //model.Series.Add(sinSeries);
            //model.Series.Add(cosSeries);

            model.Series.Add(sqrtSeries);
            //model.Series.Add(sqrtMathSeries);
            //model.Series.Add(cosMathSeries);
            //model.Series.Add(tanSeries);
            //model.Series.Add(lnSeries);
            //model.Series.Add(lnMathSeries);

            return model;
        }
    }
}
